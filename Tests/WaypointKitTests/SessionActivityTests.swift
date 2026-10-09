import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct SessionActivityTests {
    func send(_ h: HookHarness, _ event: String, at: Date, id: String? = nil, tool: String = "Bash") throws {
        var object: [String: Any] = ["session_id": HookHarness.sessionID, "cwd": "/Users/me/dev/ledger", "tool_name": tool, "prompt": "work"]
        if let id { object["tool_use_id"] = id }
        let input = try #require(HookInput(event: event, object: object))
        h.processor.handle(input, at: at)
    }

    @Test func fullTurnDistinguishesWorkToolApprovalAndInputWaiting() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        let s = try #require(try h.session())
        #expect(SessionActivityRules.activity(s, now: t0) == .waiting)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        #expect(SessionActivityRules.activity(s, now: t0 + 1) == .working)
        try send(h, "PreToolUse", at: t0 + 2, id: "a")
        #expect(SessionActivityRules.activity(s, now: t0 + 25 * 60) == .toolRunning)
        #expect(SessionRules.state(of: s, now: t0 + 25 * 60) == .live)
        try send(h, "PermissionRequest", at: t0 + 3)
        #expect(SessionActivityRules.activity(s, now: t0 + 25 * 60) == .approval)
        try send(h, "PostToolUse", at: t0 + 4, id: "a")
        #expect(SessionActivityRules.activity(s, now: t0 + 4) == .working)
        try send(h, "Stop", at: t0 + 5)
        #expect(SessionActivityRules.activity(s, now: t0 + 25 * 60) == .waiting)
        #expect(SessionFormat.activityText(s, now: t0 + 25 * 60).hasPrefix("입력 대기"))
    }

    @Test func parallelToolsFinishIndependentlyEvenWhenReplayIsOutOfOrder() throws {
        let h = try HookHarness()
        try send(h, "PreToolUse", at: t0, id: "a")
        try send(h, "PreToolUse", at: t0 + 1, id: "b")
        let s = try #require(try h.session())
        try send(h, "PostToolUse", at: t0 + 3, id: "b")
        #expect(SessionActivityRules.activity(s, now: t0 + 3) == .toolRunning)
        #expect(Set(SessionActivityRules.tools(s).keys) == ["a"])
        try send(h, "PostToolUseFailure", at: t0 + 2, id: "a")
        #expect(SessionActivityRules.tools(s).isEmpty)
        #expect(s.lastSeenAt == t0 + 3 && s.activityAt == t0 + 3)
        #expect(SessionActivityRules.activity(s, now: t0 + 3) == .working)
        // 과거 호출 시작/Stop이 현재 상태를 되돌리지 않는다.
        try send(h, "PreToolUse", at: t0, id: "a")
        try send(h, "Stop", at: t0 + 1)
        #expect(SessionActivityRules.tools(s).isEmpty)
        #expect(SessionActivityRules.activity(s, now: t0 + 3) == .working)
    }

    @Test func missingHeartbeatBecomesIdleButNeverClaimsFailure() throws {
        let h = try HookHarness()
        try send(h, "UserPromptSubmit", at: t0)
        let s = try #require(try h.session())
        #expect(SessionActivityRules.activity(s, now: t0 + 16 * 60) == .idle)
        #expect(SessionFormat.activityText(s, now: t0 + 16 * 60).hasPrefix("활동 없음"))
        let card = h.project.makeCard(in: h.context, title: "work", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: h.context)
        h.processor.sweep(now: t0 + 31 * 60, probe: { _ in nil })
        #expect(SessionActivityRules.activity(s, now: t0 + 31 * 60) == .expired)
        #expect(card.status == .next && card.doneAt == nil)
        let detached = try #require((card.events ?? []).first { $0.type == .cardDetached })
        #expect(CardHistoryFormat.line(for: detached)?.text.hasPrefix("추적 만료") == true)
        try send(h, "UserPromptSubmit", at: t0 + 32 * 60)
        #expect(SessionActivityRules.activity(s, now: t0 + 32 * 60) == .working)
        #expect(s.endReason == nil)
        #expect(CardHistoryFormat.line(for: detached)?.text.hasPrefix("추적 만료") == true)
    }

    @Test func endedSessionAndSubagentWorkAreNotConfusedWithInputWaiting() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        let parent = try #require(try h.session())
        let child = makeSession(h.context, h.project, id: "child", startedAt: t0, parent: parent)
        child.activityRaw = SessionActivity.working.rawValue
        #expect(SessionActivityRules.activity(parent, now: t0) == .toolRunning)
        h.processor.finish(parent, at: t0 + 1, reason: "logout")
        #expect(SessionActivityRules.activity(parent, now: t0 + 1) == .ended)
        #expect(child.endedAt == t0 + 1)
    }

    @Test func oldSessionsRemainReadableAndToolEvidenceSurvivesReload() throws {
        let h = try HookHarness()
        try send(h, "PreToolUse", at: t0, id: "a", tool: "Read")
        let s = try #require(try h.session())
        let ctx = ModelContext(h.container)
        let reloaded = try #require(try ctx.fetch(FetchDescriptor<Session>()).first)
        #expect(SessionActivityRules.tools(reloaded)["a"] == "Read")
        #expect(SessionActivityRules.activity(reloaded, now: t0 + 20 * 60) == .toolRunning)
        SessionActivityRules.reset(s)
        #expect(SessionActivityRules.activity(s, now: t0) == .recent)
        #expect(SessionActivityRules.activity(s, now: t0 + 20 * 60) == .idle)
    }

    @Test func codexUsesTheSameActivityRulesAndPublishesThemThroughMCP() throws {
        let h = try HookHarness()
        for (event, time) in [("SessionStart", t0), ("UserPromptSubmit", t0 + 1), ("PreToolUse", t0 + 2)] {
            let input = try #require(HookInput(event: event, object: ["session_id": "codex-real", "cwd": "/Users/me/dev/ledger", "tool_name": "Bash", "tool_use_id": "tool-1", "prompt": "work"], provider: .codex))
            h.processor.handle(input, at: time)
        }
        let s = try #require(try h.session("codex:codex-real"))
        let card = h.project.makeCard(in: h.context, title: "work", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: h.context)
        let tools = MCPTools(context: h.context, now: { t0 + 20 * 60 })
        let result = try tools.call("card_get", ["id": .string(card.displayID)])
        #expect(result["sessions"]?.arrayValue?.first?["activity"] == "toolRunning")
        #expect(result["sessions"]?.arrayValue?.first?["activityLabel"]?.stringValue?.contains("Bash") == true)
    }

    // 늦게 온 완료 기록은 그 호출만 닫는다. 같은 이름의 다른 호출은 남고, 기록과 같은 시각에 시작한 호출도 닫힌다.
    @Test func latePostToolUseClosesOnlyItsOwnCall() throws {
        let h = try HookHarness()
        try send(h, "PreToolUse", at: t0, id: "a")
        try send(h, "PreToolUse", at: t0 + 1, id: "b")
        try send(h, "PreToolUse", at: t0 + 5, id: "c")
        let s = try #require(try h.session())
        try send(h, "PostToolUse", at: t0 + 2, id: "a")
        #expect(Set(SessionActivityRules.tools(s).keys) == ["b", "c"])
        try send(h, "PostToolUse", at: t0 + 1, id: "b")
        #expect(Set(SessionActivityRules.tools(s).keys) == ["c"])
        #expect(SessionActivityRules.activity(s, now: t0 + 5) == .toolRunning)
    }

    // 늦게 온 완료 기록이 마지막 도구를 닫아도 승인 대기는 풀리지 않는다.
    @Test func latePostToolUseKeepsApprovalWaiting() throws {
        let h = try HookHarness()
        try send(h, "PreToolUse", at: t0, id: "a")
        try send(h, "PermissionRequest", at: t0 + 5)
        let s = try #require(try h.session())
        try send(h, "PostToolUse", at: t0 + 2, id: "a")
        #expect(SessionActivityRules.tools(s).isEmpty)
        #expect(SessionActivityRules.activity(s, now: t0 + 5) == .approval)
    }

    // 호출 ID가 없는 완료 기록은 도구 이름으로 닫는다(늦게 와도, 제때 와도).
    @Test func postToolUseWithoutCallIDClosesByToolName() throws {
        let h = try HookHarness()
        try send(h, "PreToolUse", at: t0, tool: "Bash")
        try send(h, "PreToolUse", at: t0 + 1, tool: "Read")
        try send(h, "PreToolUse", at: t0 + 5, id: "g", tool: "Grep")
        let s = try #require(try h.session())
        try send(h, "PostToolUse", at: t0 + 2, tool: "Bash")
        #expect(SessionActivityRules.tools(s).values.sorted() == ["Grep", "Read"])
        try send(h, "PostToolUse", at: t0 + 6, tool: "Read")
        #expect(SessionActivityRules.tools(s).values.sorted() == ["Grep"])
    }

    // 마지막 활동에서 딱 멈춤 시간만큼 지난 순간은 아직 활동 없음이 아니다.
    @Test func exactlyAtTimeoutIsNotYetIdle() throws {
        let h = try HookHarness()
        try send(h, "UserPromptSubmit", at: t0)
        let s = try #require(try h.session())
        #expect(SessionActivityRules.activity(s, now: t0 + SessionRules.defaultStallTimeout) == .working)
        #expect(SessionActivityRules.activity(s, now: t0 + SessionRules.defaultStallTimeout + 1) == .idle)
    }

    // 끝난 까닭 칸이 빈 세션은 종료 기록의 이유로 추적 만료를 가린다. 다른 기록의 이유는 보지 않는다.
    @Test func endedSessionWithoutReasonFieldReadsItFromEndEvent() throws {
        let h = try HookHarness()
        let expired = makeSession(h.context, h.project, id: "expired")
        expired.endedAt = t0 + 10
        Event.record(.sessionEnd, in: h.context, session: expired, at: t0 + 10, payload: ["reason": .string(SessionSweep.reasonInactive)])
        Event.record(.cardDetached, in: h.context, session: expired, at: t0 + 20, payload: ["reason": "logout"])
        #expect(SessionActivityRules.activity(expired, now: t0 + 30) == .expired)
        let closed = makeSession(h.context, h.project, id: "closed")
        closed.endedAt = t0 + 10
        Event.record(.sessionEnd, in: h.context, session: closed, at: t0 + 10, payload: ["reason": "logout"])
        Event.record(.cardDetached, in: h.context, session: closed, at: t0 + 20, payload: ["reason": .string(SessionSweep.reasonInactive)])
        #expect(SessionActivityRules.activity(closed, now: t0 + 30) == .ended)
    }
}
