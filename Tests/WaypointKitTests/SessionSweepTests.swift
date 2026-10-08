import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// `SessionEnd`가 오지 않은 세션 정리(SPEC 5장 「종료 판정」).
@Suite struct SessionSweepTests {

    static let pid = 4242
    let alive: SessionSweep.Probe = { _ in SessionSweep.ProcessStatus(startedAt: t0 - 3600) }
    let gone: SessionSweep.Probe = { _ in nil }

    @discardableResult
    func send(_ h: HookHarness, _ name: String, at date: Date, pid: Int? = SessionSweepTests.pid) throws -> String? {
        h.processor.handle(event: nil, json: try fixture(name), at: date, claudePid: pid)
    }

    // MARK: - 판정(순수 함수)

    @Test func verdictWithPid() {
        let now = t0 + minutes(30)
        #expect(SessionSweep.verdict(pid: 10, lastSeenAt: t0, now: now, probe: gone) == .end(reason: "process-gone"))
        #expect(SessionSweep.verdict(pid: 10, lastSeenAt: t0, now: now, probe: alive) == .keep)
        // 시작 시각을 모르면 살아 있는 것으로
        #expect(SessionSweep.verdict(pid: 10, lastSeenAt: t0, now: now) { _ in .init(startedAt: nil) } == .keep)
        // PID가 있으면 24시간이 지나도 프로세스가 살아 있는 한 둔다
        #expect(SessionSweep.verdict(pid: 10, lastSeenAt: t0, now: t0 + 48 * 3600, probe: alive) == .keep)
    }

    @Test func verdictPidReuse() {
        // 마지막 훅 뒤에 시작한 프로세스 = PID를 재사용한 다른 프로세스
        let later: SessionSweep.Probe = { _ in .init(startedAt: t0 + 10) }
        #expect(SessionSweep.verdict(pid: 10, lastSeenAt: t0, now: t0 + 60, probe: later) == .end(reason: "process-gone"))
        // outbox receivedAt은 초 단위로 잘리므로 여유 안쪽은 같은 프로세스
        let edge: SessionSweep.Probe = { _ in .init(startedAt: t0 + SessionSweep.startTolerance) }
        #expect(SessionSweep.verdict(pid: 10, lastSeenAt: t0, now: t0 + 60, probe: edge) == .keep)
    }

    @Test func verdictWithoutPid() {
        var probed = false
        let probe: SessionSweep.Probe = { _ in probed = true; return nil }
        #expect(SessionSweep.verdict(pid: nil, lastSeenAt: t0, now: t0 + 30 * 60, probe: probe) == .keep)
        #expect(SessionSweep.verdict(pid: nil, lastSeenAt: t0, now: t0 + 30 * 60 + 1, probe: probe) == .end(reason: "tracking-expired-30m"))
        #expect(!probed)
    }

    // MARK: - 세션에 적용

    @Test func processGoneEndsSessionDetachesAndRestoresStatus() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        try send(h, "doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        #expect(main.claudePid == Self.pid)
        CardLifecycle.attach(card, main, at: t0, in: h.context)
        try send(h, "doc-SubagentStart", at: t0 + 1)
        let sub = try #require(try h.session(HookHarness.agentID))
        #expect(sub.claudePid == nil) // 하위 세션에는 적지 않는다
        #expect(card.status == .active)

        let now = t0 + minutes(3)
        #expect(h.processor.sweep(now: now, probe: gone) == 1)
        #expect(main.endedAt == now)
        #expect(sub.endedAt == now)
        #expect(main.lastSeenAt == t0 + 1) // 마지막 활동은 그대로
        #expect(main.cachedState == .ended)
        #expect(card.status == .next)
        #expect(card.doneAt == nil)
        #expect(card.openCardSessions.isEmpty)
        let end = try #require((main.events ?? []).first { $0.type == .sessionEnd })
        #expect(end.payloadValues["reason"]?.stringValue == "process-gone")
        #expect(!h.context.hasChanges) // 저장까지

        // 두 번 해도 그대로
        #expect(h.processor.sweep(now: now + 60, probe: gone) == 0)
    }

    @Test func aliveProcessKeepsSession() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0)
        var asked: [Int] = []
        #expect(h.processor.sweep(now: t0 + minutes(30)) { asked.append($0); return .init(startedAt: t0 - 5) } == 0)
        #expect(asked == [Self.pid])
        #expect(try h.session()?.endedAt == nil)
    }

    @Test func noPidExpiresAfter30Minutes() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0, pid: nil)
        let main = try #require(try h.session())
        #expect(main.claudePid == nil)
        #expect(h.processor.sweep(now: t0 + 29 * 60, probe: gone) == 0)
        #expect(main.endedAt == nil)
        #expect(h.processor.sweep(now: t0 + 31 * 60, probe: gone) == 1)
        #expect(main.endedAt == t0 + 31 * 60)
        let end = (main.events ?? []).first { $0.type == .sessionEnd }
        #expect(end?.payloadValues["reason"]?.stringValue == "tracking-expired-30m")
    }

    @Test func lateHookAfterSweepRevivesButOlderDoesNot() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        let now = t0 + minutes(5)
        h.processor.sweep(now: now, probe: gone)
        #expect(main.endedAt == now)

        // 정리 전 시각의 늦은 기록(outbox)은 되살리지 않는다
        try send(h, "doc-Stop", at: now - 60)
        #expect(main.endedAt == now)
        // 정리 뒤 시각의 훅(resume 등)은 되살리고 새 PID를 적는다
        try send(h, "doc-SessionStart", at: now + 60, pid: 5555)
        #expect(main.endedAt == nil)
        #expect(main.claudePid == 5555)
        #expect(h.processor.sweep(now: now + 120) { $0 == 5555 ? .init(startedAt: now + 30) : nil } == 0)
    }

    @Test func pidIsFilledByAnyHookAndOverwrittenOnlyByNewer() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0, pid: nil)
        let main = try #require(try h.session())
        #expect(main.claudePid == nil)
        // SessionStart가 아닌 훅, 서브에이전트 안의 훅도 메인 세션 PID를 채운다
        try send(h, "doc-SubagentStart", at: t0 + 1, pid: 111)
        #expect(main.claudePid == 111)
        #expect(try h.session(HookHarness.agentID)?.claudePid == nil)
        // 더 새 훅(resume한 새 프로세스)은 바꾼다
        try send(h, "doc-UserPromptSubmit", at: t0 + 60, pid: 222)
        #expect(main.claudePid == 222)
        // 옛 시각의 늦은 기록은 되돌리지 않는다
        try send(h, "doc-Stop", at: t0 + 30, pid: 111)
        #expect(main.claudePid == 222)
        // PID 없는 훅은 지우지 않는다
        try send(h, "doc-Stop", at: t0 + 90, pid: nil)
        #expect(main.claudePid == 222)
    }

    @Test func resumedHookWithoutPidDoesNotRetainDeadProcess() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        h.processor.sweep(now: t0 + 60, probe: gone)
        try send(h, "doc-SessionStart", at: t0 + 120, pid: nil)
        #expect(main.endedAt == nil && main.claudePid == nil)
        #expect(h.processor.sweep(now: t0 + 180, probe: gone) == 0)
    }

    @Test func sweepIgnoresEndedAndSubagentSessions() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0)
        try send(h, "doc-SubagentStart", at: t0 + 1)
        let sub = try #require(try h.session(HookHarness.agentID))
        sub.claudePid = 999 // 하위 세션은 메인 세션을 통해서만 끝난다
        var asked: [Int] = []
        h.processor.sweep(now: t0 + 60) { asked.append($0); return .init(startedAt: nil) }
        #expect(asked == [Self.pid])
        #expect(sub.endedAt == nil)
    }

    // 자동 정리로 끝난 세션만 다시 이을 수 있다. 종료 기록의 이유만 보고 다른 기록의 이유는 보지 않는다.
    @Test func onlyAutoEndedSessionsCanReconnect() throws {
        let h = try HookHarness()
        let open = makeSession(h.context, h.project, id: "open")
        #expect(SessionSweep.canReconnect(open))
        let swept = makeSession(h.context, h.project, id: "swept")
        swept.endedAt = t0 + 10
        Event.record(.sessionEnd, in: h.context, session: swept, at: t0 + 10, payload: ["reason": .string(SessionSweep.reasonProcessGone)])
        Event.record(.cardDetached, in: h.context, session: swept, at: t0 + 20, payload: ["reason": "logout"])
        #expect(SessionSweep.canReconnect(swept))
        let closed = makeSession(h.context, h.project, id: "closed")
        closed.endedAt = t0 + 10
        Event.record(.sessionEnd, in: h.context, session: closed, at: t0 + 10, payload: ["reason": "logout"])
        Event.record(.cardDetached, in: h.context, session: closed, at: t0 + 20, payload: ["reason": .string(SessionSweep.reasonProcessGone)])
        #expect(!SessionSweep.canReconnect(closed))
    }

    // MARK: - macOS 프로세스 확인

    #if os(macOS)
    @Test func systemProbeSeesSelfAndNotExitedProcess() throws {
        let me = try #require(SessionSweep.systemProbe(Int(getpid())))
        let started = try #require(me.startedAt)
        #expect(started <= Date())
        #expect(started > Date() - 24 * 3600)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try task.run()
        task.waitUntilExit()
        #expect(SessionSweep.systemProbe(Int(task.processIdentifier)) == nil)
        #expect(SessionSweep.systemProbe(0) == nil)
        #expect(SessionSweep.systemProbe(-5) == nil)
    }

    // PID 1(launchd)은 살아 있어도 세션 프로세스로 보지 않는다.
    @Test func systemProbeIgnoresLaunchd() {
        #expect(SessionSweep.systemProbe(1) == nil)
    }
    #endif
}
