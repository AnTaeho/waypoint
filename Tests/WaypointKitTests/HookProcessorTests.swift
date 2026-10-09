import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct HookProcessorTests {

    @Test func sessionStartCreatesSessionFromSubfolder() throws {
        let h = try HookHarness()
        let text = try #require(try h.send("doc-SessionStart", at: t0))
        let s = try #require(try h.session())
        #expect(s.kind == .main)
        #expect(s.project === h.project)
        #expect(s.startedAt == t0)
        #expect(s.gitBranch == "feat/ocr-mapping")
        #expect(SessionRules.state(of: s, now: t0) == .stalled)
        #expect(SessionActivityRules.activity(s, now: t0) == .waiting)
        #expect(text.contains("LDG"))
        #expect(text.contains(HookHarness.sessionID))
        #expect((s.events ?? []).filter { $0.type == .sessionStart }.count == 1)
    }

    @Test func unregisteredFolderProvidesIdentityWithoutCreatingSession() throws {
        let h = try HookHarness()
        let text = try h.send("doc-SessionStart-unregistered", at: t0)
        #expect(text?.hasPrefix(SessionContext.unregistered) == true)
        #expect(text?.contains("sessionId: \(try #require(HookInput(event: nil, json: fixture("doc-SessionStart-unregistered"))).sessionID)") == true)
        #expect(try h.context.fetchCount(FetchDescriptor<Session>()) == 0)
    }

    @Test func sessionStartTwiceKeepsOneSession() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SessionStart", at: t0 + 60)
        #expect(try h.context.fetchCount(FetchDescriptor<Session>()) == 1)
        #expect(try h.session()?.lastSeenAt == t0 + 60)
    }

    @Test func heartbeatMovesLastSeenForwardOnly() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-UserPromptSubmit", at: t0 + minutes(20))
        let s = try #require(try h.session())
        #expect(SessionRules.state(of: s, now: t0 + minutes(21)) == .live)
        try h.send("doc-Stop", at: t0 + minutes(5)) // 늦게 온 옛 기록
        #expect(s.lastSeenAt == t0 + minutes(20))
    }

    @Test func eventsWithoutSessionStartCreateSession() throws {
        let h = try HookHarness()
        try h.send("doc-UserPromptSubmit", at: t0)
        let s = try #require(try h.session())
        #expect(s.startedAt == t0)
        #expect((s.events ?? []).contains { $0.type == .sessionStart })
    }

    @Test func subagentFlowAttachesCardFromPrompt() throws {
        let h = try HookHarness()
        let c14 = h.project.makeCard(in: h.context, title: "영수증 매핑", status: .next, at: t0)
        let c16 = try makeCardNumbered(16, in: h)
        try h.send("doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        CardLifecycle.attach(c14, main, at: t0, in: h.context)

        try h.send("doc-PreToolUse-Agent", at: t0 + 10)
        try h.send("doc-SubagentStart", at: t0 + 11)
        let sub = try #require(try h.session(HookHarness.agentID))
        #expect(sub.kind == .subagent)
        #expect(sub.parent === main)
        #expect(sub.agentName == "test-writer")
        #expect(c16.status == .active)
        #expect(c16.openCardSessions.first?.session === sub)

        let rows = DashboardQuery.rows(for: h.project, now: t0 + 20)
        #expect(rows.map(\.card?.number) == [c14.number, 16])
        #expect(rows.map(\.depth) == [0, 1])

        try h.send("doc-PostToolUse-Write-subagent", at: t0 + 20)
        let files = (c16.events ?? []).filter { $0.type == .fileChanged }
        #expect(files.count == 1)
        #expect(files.first?.payloadValues["path"]?.stringValue == "LedgerTests/ReceiptParserTests.swift")
        #expect(files.first?.payloadValues["added"]?.intValue == 3)
        #expect(files.first?.session === sub)

        try h.send("doc-SubagentStop", at: t0 + 30)
        #expect(sub.endedAt == t0 + 30)
        #expect(c16.status == .next)
        #expect(main.endedAt == nil)
        #expect(c14.status == .active)
    }

    @Test func mainSessionFileChangeAndCommit() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        try h.send("doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        CardLifecycle.attach(card, main, at: t0, in: h.context)
        main.gitBranch = nil

        try h.send("doc-PostToolUse-Edit", at: t0 + 10)
        let file = try #require((card.events ?? []).first { $0.type == .fileChanged })
        #expect(file.payloadValues["path"]?.stringValue == "Ledger/OCR/ReceiptParser.swift")
        #expect(file.payloadValues["added"]?.intValue == 3)
        #expect(file.payloadValues["removed"]?.intValue == 2)

        try h.send("doc-PostToolUse-Bash-commit", at: t0 + 20)
        let commit = try #require((card.events ?? []).first { $0.type == .commit })
        #expect(commit.payloadValues["hash"]?.stringValue == "4c1d9e0")
        #expect(commit.payloadValues["message"]?.stringValue == "영수증 파서 합계 규칙")
        #expect(main.gitBranch == "feat/ocr-mapping")
    }

    @Test func fileChangeWithoutCardIsKeptOnProject() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PostToolUse-Edit", at: t0 + 10)
        let events = (h.project.events ?? []).filter { $0.type == .fileChanged }
        #expect(events.count == 1)
        #expect(events.first?.card == nil)
    }

    @Test func sessionEndDetachesEverythingAndNeverMarksDone() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        try h.send("doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        CardLifecycle.attach(card, main, at: t0, in: h.context)
        try h.send("doc-SubagentStart", at: t0 + 1)
        let sub = try #require(try h.session(HookHarness.agentID))

        try h.send("doc-SessionEnd", at: t0 + 60)
        #expect(main.endedAt == t0 + 60)
        #expect(sub.endedAt == t0 + 60)
        #expect(card.status == .next)
        #expect(card.doneAt == nil)
        #expect(DashboardQuery.rows(for: h.project, now: t0 + 61).isEmpty)
        let end = (main.events ?? []).first { $0.type == .sessionEnd }
        #expect(end?.payloadValues["reason"]?.stringValue == "prompt_input_exit")

        // 끝난 뒤 늦게 온 옛 기록은 세션을 되살리지 않는다
        try h.send("doc-Stop", at: t0 + 30)
        #expect(main.endedAt == t0 + 60)
        // 같은 세션 ID로 다시 시작(resume)하면 살아난다
        try h.send("doc-SessionStart", at: t0 + 120)
        #expect(main.endedAt == nil)
    }

    @Test func pendingSpawnExpiresAndOtherTypesDoNotMatch() throws {
        let h = try HookHarness()
        _ = try makeCardNumbered(16, in: h)
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PreToolUse-Agent", at: t0)
        try h.send("doc-SubagentStart", at: t0 + HookProcessor.pendingLifetime + 1)
        #expect(h.card(16)?.status == .next)
        #expect(try h.session(HookHarness.agentID) != nil)
    }

    @Test func unknownSubagentStopIsIgnored() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SubagentStop", at: t0 + 1)
        #expect(try h.context.fetchCount(FetchDescriptor<Session>()) == 1)
        #expect(try h.session()?.endedAt == nil)
    }

    @Test func unreadableBodyIsIgnored() throws {
        let h = try HookHarness()
        #expect(h.processor.handle(event: "SessionStart", json: Data("not json".utf8), at: t0) == nil)
        #expect(h.processor.handle(event: "SessionStart", json: Data("{}".utf8), at: t0) == nil)
        #expect(try h.context.fetchCount(FetchDescriptor<Session>()) == 0)
    }

    /// 번호를 맞춰 카드를 만든다(`nextCardNumber`를 당겨서).
    private func makeCardNumbered(_ number: Int, in h: HookHarness) throws -> Card {
        h.project.nextCardNumber = number
        let card = h.project.makeCard(in: h.context, title: "파서 단위 테스트", status: .next, at: t0)
        try #require(card.number == number)
        return card
    }
}

@Suite struct ArchivedProjectHookTests {
    @Test func archivedFolderGetsNoContextAndNoSession() throws {
        let h = try HookHarness()
        h.project.archivedAt = t0
        try h.context.save()
        let text = try h.send("doc-SessionStart", at: t0 + 60)
        #expect(text == "")
        _ = try h.send("doc-UserPromptSubmit", at: t0 + 90)
        #expect(try h.context.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try h.context.fetchCount(FetchDescriptor<Event>()) == 0)
    }

    @Test func liveSessionStopsRecordingWhenArchived() throws {
        let h = try HookHarness()
        _ = try h.send("doc-SessionStart", at: t0)
        let s = try #require(try h.session())
        let eventCount = (h.project.events ?? []).count
        h.project.archivedAt = t0 + 30
        try h.context.save()
        _ = try h.send("doc-UserPromptSubmit", at: t0 + 60)
        #expect(s.lastSeenAt == t0)
        #expect(try h.send("doc-SessionStart", at: t0 + 90) == "")
        #expect((h.project.events ?? []).count == eventCount)
        // 보관을 풀면 다시 기록한다
        h.project.archivedAt = nil
        try h.context.save()
        _ = try h.send("doc-UserPromptSubmit", at: t0 + 120)
        #expect(s.lastSeenAt == t0 + 120)
    }
}

/// 경계·재수신·기본값: 같은 시각에 온 훅, 시간 폭의 끝, 다시 받은 훅.
@Suite struct HookProcessorBoundaryTests {
    /// 픽스처 본문의 필드를 바꿔 보낸다. 값이 `NSNull`이면 그 필드를 뺀다.
    @discardableResult
    func send(_ h: HookHarness, _ name: String, at date: Date, pid: Int? = nil,
              override: [String: Any] = [:]) throws -> String? {
        var object = try #require(try JSONSerialization.jsonObject(with: try fixture(name)) as? [String: Any])
        for (key, value) in override { object[key] = value is NSNull ? nil : value }
        return h.processor.handle(event: nil, json: try JSONSerialization.data(withJSONObject: object), at: date,
                                  claudePid: pid)
    }

    // 종류를 안 준 Agent 호출은 종류 없이 시작한 서브에이전트와 짝지어 카드를 잇는다.
    @Test func untypedAgentCallPairsWithUntypedSubagent() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "파서 테스트", status: .next, at: t0)
        try h.send("doc-SessionStart", at: t0)
        try send(h, "doc-PreToolUse-Agent", at: t0 + 10,
                 override: ["tool_input": ["prompt": "[LDG-\(card.number)] 테스트를 써 줘"]])
        try send(h, "doc-SubagentStart", at: t0 + 11, override: ["agent_type": NSNull()])
        let sub = try #require(try h.session(HookHarness.agentID))
        #expect(card.openCardSessions.first?.session === sub)
    }

    // 대기 시간(10분)의 끝에 딱 맞춰 시작한 서브에이전트까지는 짝짓는다.
    @Test func subagentStartingAtLifetimeEdgeStillPairs() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "파서 테스트", status: .next, at: t0)
        try h.send("doc-SessionStart", at: t0)
        try send(h, "doc-PreToolUse-Agent", at: t0, override: [
            "tool_input": ["prompt": "[LDG-\(card.number)] 테스트", "subagent_type": "test-writer"],
        ])
        try h.send("doc-SubagentStart", at: t0 + HookProcessor.pendingLifetime)
        #expect(card.status == .active)
    }

    // 같은 Agent 호출을 10분 끝에 다시 받아도 대기 목록에 두 번 올리지 않는다.
    @Test func agentCallRedeliveredAtLifetimeEdgeIsQueuedOnce() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PreToolUse-Agent", at: t0)
        try h.send("doc-PreToolUse-Agent", at: t0 + HookProcessor.pendingLifetime)
        #expect(h.processor.pendingSpawns[HookHarness.sessionID]?.count == 1)
    }

    // 세션 시작 훅을 못 받았어도 서브에이전트 시작이 부모 세션까지 만든다.
    @Test func subagentStartCreatesMissingParent() throws {
        let h = try HookHarness()
        try h.send("doc-SubagentStart", at: t0)
        let main = try #require(try h.session())
        let sub = try #require(try h.session(HookHarness.agentID))
        #expect(main.kind == .main && main.project === h.project)
        #expect(sub.parent === main)
    }

    // 끝난 서브에이전트가 같은 ID로 다시 시작하면 다시 연다.
    @Test func restartedSubagentIsReopened() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SubagentStart", at: t0 + 1)
        try h.send("doc-SubagentStop", at: t0 + 10)
        let sub = try #require(try h.session(HookHarness.agentID))
        #expect(sub.endedAt == t0 + 10)
        try h.send("doc-SubagentStart", at: t0 + 20)
        #expect(sub.endedAt == nil)
        #expect(sub.cachedState == .live)
        #expect(sub.lastSeenAt == t0 + 20)
        #expect(try h.context.fetchCount(FetchDescriptor<Session>()) == 2)
    }

    // 도구 실패 훅이 그 세션의 첫 훅이어도 세션을 만든다.
    @Test func toolFailureCreatesMissingSession() throws {
        let h = try HookHarness()
        h.processor.handle(event: nil, json: try HookCheckTests.bash("ls", event: "PostToolUseFailure", response: nil,
                                                                     error: "Exit code 1"), at: t0)
        let main = try #require(try h.session())
        #expect(main.project === h.project && main.startedAt == t0)
    }

    // 메인 세션이 끝난 뒤 늦게 온 서브에이전트 종료는 메인 세션을 되살리지 않는다.
    @Test func lateSubagentStopDoesNotReviveEndedMain() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SubagentStart", at: t0 + 1)
        try h.send("doc-SessionEnd", at: t0 + 60)
        try h.send("doc-SubagentStop", at: t0 + 90)
        let main = try #require(try h.session())
        #expect(main.endedAt == t0 + 60)
        #expect((main.events ?? []).filter { $0.type == .sessionStart }.count == 1)
    }

    // 끝난 시각과 같은 시각의 훅은 세션을 되살리지 않는다(그 뒤 시각만).
    @Test func hookAtEndInstantDoesNotRevive() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SessionEnd", at: t0 + 60)
        try h.send("doc-Stop", at: t0 + 60)
        #expect(try h.session()?.endedAt == t0 + 60)
    }

    // 같은 도구 호출의 커밋 훅을 다시 받으면 커밋을 한 번만 남긴다.
    @Test func redeliveredCommitIsRecordedOnce() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PostToolUse-Bash-commit", at: t0 + 20)
        try h.send("doc-PostToolUse-Bash-commit", at: t0 + 25)
        #expect((h.project.events ?? []).filter { $0.type == .commit }.count == 1)
    }

    // 같은 도구 호출의 파일 변경은 10분 끝에 다시 받아도 한 번만 남긴다.
    @Test func editRedeliveredAtWindowEdgeIsRecordedOnce() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PostToolUse-Edit", at: t0 + 10)
        try h.send("doc-PostToolUse-Edit", at: t0 + 10 + HookProcessor.redeliveryWindow)
        #expect((h.project.events ?? []).filter { $0.type == .fileChanged }.count == 1)
    }

    // 마지막 활동과 같은 시각에 온 훅의 PID는 새것으로 보고 바꾼다.
    @Test func hookAtSameInstantReplacesPid() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0, pid: 4100)
        try send(h, "doc-Stop", at: t0, pid: 4200)
        #expect(try h.session()?.claudePid == 4200)
    }

    // 서브에이전트 안에서 난 훅도 부모 세션의 캐시 상태를 live로 돌린다.
    @Test func subagentHookMarksParentLive() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SubagentStart", at: t0 + 1)
        let main = try #require(try h.session())
        main.cachedState = .stalled
        try h.send("doc-PostToolUse-Write-subagent", at: t0 + 20)
        #expect(main.cachedState == .live)
    }

    // 종료 훅은 그 세션의 마지막 활동 시각도 옮긴다(메인·서브에이전트 모두).
    @Test func endHooksMoveLastSeen() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SubagentStart", at: t0 + 1)
        try h.send("doc-SubagentStop", at: t0 + 30)
        #expect(try h.session(HookHarness.agentID)?.lastSeenAt == t0 + 30)
        try h.send("doc-SessionEnd", at: t0 + 60)
        #expect(try h.session()?.lastSeenAt == t0 + 60)
    }

    // 세션이 끝나면 그 세션의 Agent 호출 기억만 지우고 다른 세션 것은 둔다.
    @Test func endedSessionForgetsOnlyItsOwnAgentCalls() throws {
        let h = try HookHarness()
        let other = "0ther-session-0001"
        try h.send("doc-SessionStart", at: t0)
        try send(h, "doc-SessionStart", at: t0, override: ["session_id": other])
        try h.send("doc-PreToolUse-Agent", at: t0 + 10)
        try send(h, "doc-PreToolUse-Agent", at: t0 + 10, override: ["session_id": other])
        #expect(h.processor.seenSpawns.count == 2)
        try h.send("doc-SessionEnd", at: t0 + 20)
        #expect(Array(h.processor.seenSpawns.keys) == ["\(other)|toolu_01ABC123"])
        #expect(h.processor.pendingSpawns[HookHarness.sessionID] == nil)
        #expect(h.processor.pendingSpawns[other]?.count == 1)
    }

    // 새 처리기와 읽지 못한 본문은 저장 실패로 치지 않는다.
    @Test func unreadableBodyIsNotASaveFailure() throws {
        let h = try HookHarness()
        #expect(!h.processor.lastSaveFailed)
        h.processor.handle(event: "Stop", json: Data("not json".utf8), at: t0)
        #expect(!h.processor.lastSaveFailed)
    }

    // 훅 입력을 바로 넘기면 따로 말하지 않아도 블록을 돌려준다.
    @Test func parsedInputDeliversBlockByDefault() throws {
        let h = try HookHarness()
        let text = h.processor.handle(try fixtureInput("doc-SessionStart"), at: t0)
        #expect(text?.hasPrefix("Waypoint: LDG") == true)
    }
}
