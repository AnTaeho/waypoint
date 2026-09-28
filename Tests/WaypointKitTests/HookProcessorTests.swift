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
        #expect(SessionRules.state(of: s, now: t0) == .live)
        #expect(text.contains("LDG"))
        #expect(text.contains(HookHarness.sessionID))
        #expect((s.events ?? []).filter { $0.type == .sessionStart }.count == 1)
    }

    @Test func unregisteredFolderIsIgnoredWithOneLine() throws {
        let h = try HookHarness()
        let text = try h.send("doc-SessionStart-unregistered", at: t0)
        #expect(text == SessionContext.unregistered)
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
