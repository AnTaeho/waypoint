import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 흡수 한 번마다 새 context에서 처리하는 `HookProcessor.absorbOutbox`(디스크 SQLite 저장소).
@Suite struct OutboxAbsorbTests {
    private enum SaveFailure: Error { case diskUnavailable }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-absorb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ entries: [(String, String, Date)], to dir: URL) throws {
        let lines = try entries.map { event, name, date in
            let payload = String(decoding: try fixture(name), as: UTF8.self).replacingOccurrences(of: "\n", with: "")
            return #"{"event":"\#(event)","receivedAt":\#(Int(date.timeIntervalSince1970)),"payload":\#(payload)}"#
        }
        try (lines.joined(separator: "\n") + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
    }

    /// 하위 세션을 넣는 저장만 실패시킨다.
    private func failSubagentInsert(_ context: ModelContext) throws {
        if context.insertedModelsArray.contains(where: { ($0 as? Session)?.kind == .subagent }) {
            throw SaveFailure.diskUnavailable
        }
        try context.save()
    }

    private func harness() throws -> (HookHarness, Card) {
        let h = try HookHarness(onDisk: true)
        h.project.nextCardNumber = 16
        let card = h.project.makeCard(in: h.context, title: "파서 단위 테스트", status: .next, at: t0)
        try h.context.save()
        try #require(card.number == 16)
        return (h, card)
    }

    /// (a)(b) 저장 실패 뒤 같은 실행·같은 처리기로 다시 흡수해도 잘못된 세션·연결이 없고, 실패 직후 메인 context가 저장소와 같다.
    @Test func sameRunRetryAfterFailedSaveLeavesNoStaleRecords() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (h, card) = try harness()
        try write([("SessionStart", "doc-SessionStart", t0),
                   ("PreToolUse", "doc-PreToolUse-Agent", t0 + 10),
                   ("SubagentStart", "doc-SubagentStart", t0 + 11)], to: dir)
        h.processor.saveContext = failSubagentInsert
        var received: [String] = []
        let first = h.processor.absorbOutbox(directory: dir) { received.append($0.event) }
        #expect(first.processed == 2 && first.retryPending)
        #expect(received == ["SessionStart", "PreToolUse"])
        #expect(IntegrationQueue.inspect(directory: dir).count == 1)
        // 실패 직후: 메인 context는 저장된 앞 두 줄만 보고, 저장소와 같다
        #expect(!h.context.hasChanges)
        let stored = ModelContext(h.container)
        let storedCard = try #require(stored.fetch(FetchDescriptor<Card>()).first)
        #expect(card.status == storedCard.status && card.status == .next)
        #expect(card.cardSessions?.count == storedCard.cardSessions?.count && card.cardSessions?.isEmpty == true)
        #expect(try h.session()?.children?.isEmpty == true)
        #expect(try h.context.fetch(FetchDescriptor<Session>()).map(\.id) == [HookHarness.sessionID])
        // 저장된 PreToolUse의 대기 항목은 실시간 처리기로 돌아온다
        #expect(h.processor.pendingSpawns[HookHarness.sessionID]?.count == 1)

        h.processor.saveContext = { try $0.save() }
        let retry = h.processor.absorbOutbox(directory: dir) { received.append($0.event) }
        #expect(retry.processed == 1 && !retry.retryPending)
        #expect(received == ["SessionStart", "PreToolUse", "SubagentStart"])
        let fresh = ModelContext(h.container)
        let ids = try fresh.fetch(FetchDescriptor<Session>()).map(\.id).sorted()
        #expect(ids == [HookHarness.agentID, HookHarness.sessionID].sorted())
        let links = try fresh.fetch(FetchDescriptor<CardSession>())
        #expect(links.count == 1 && links.first?.session?.id == HookHarness.agentID)
        #expect(card.status == .active && card.cardSessions?.count == 1)
        #expect(h.processor.pendingSpawns[HookHarness.sessionID, default: []].isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    /// (c) 실시간 훅과 흡수가 번갈아 일어나도(흡수 실패 포함) 중복·누락이 없다.
    /// 흡수 뒤 실시간 훅이 같은 세션을 고쳐 저장해도 흡수가 저장한 하위 세션·연결이 덮이지 않는다.
    @Test func liveHooksAndAbsorbInterleaveWithoutDuplicatesOrLoss() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (h, card) = try harness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PreToolUse-Agent", at: t0 + 10)
        try write([("SubagentStart", "doc-SubagentStart", t0 + 11), ("Stop", "doc-Stop", t0 + 12)], to: dir)

        h.processor.saveContext = failSubagentInsert
        let failed = h.processor.absorbOutbox(directory: dir)
        #expect(failed.processed == 0 && failed.retryPending)
        #expect(h.processor.pendingSpawns[HookHarness.sessionID]?.count == 1)

        h.processor.saveContext = { try $0.save() }
        try h.send("doc-Stop", at: t0 + 13)
        let recovered = h.processor.absorbOutbox(directory: dir)
        #expect(recovered.processed == 2 && !recovered.retryPending)
        #expect(card.status == .active && card.cardSessions?.count == 1)

        // 흡수가 고친 세션을 실시간 훅이 다시 고쳐 저장한다
        try h.send("doc-UserPromptSubmit", at: t0 + 14)
        try h.send("doc-PostToolUse-Write-subagent", at: t0 + 15)
        #expect(!h.processor.lastSaveFailed)

        let fresh = ModelContext(h.container)
        let sessions = try fresh.fetch(FetchDescriptor<Session>())
        #expect(sessions.map(\.id).sorted() == [HookHarness.agentID, HookHarness.sessionID].sorted())
        let main = try #require(sessions.first { $0.id == HookHarness.sessionID })
        let sub = try #require(sessions.first { $0.id == HookHarness.agentID })
        #expect(main.lastSeenAt == t0 + 15 && main.lastPrompt != nil)
        #expect(sub.parent?.id == main.id)
        let links = try fresh.fetch(FetchDescriptor<CardSession>())
        #expect(links.count == 1 && links.first?.session?.id == HookHarness.agentID && links.first?.card?.number == 16)
        let starts = try fresh.fetch(FetchDescriptor<Event>()).filter { $0.type == .sessionStart }
        #expect(starts.count == 2)
        let storedCard = try #require(fresh.fetch(FetchDescriptor<Card>()).first)
        #expect(storedCard.status == .active)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    // 세션 ID가 없는 줄은 저장 실패로 보지 않고 넘긴다(남겨서 다시 하지 않는다).
    @Test func lineWithoutSessionIDIsConsumedNotRetried() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (h, _) = try harness()
        try (#"{"event":"Stop","receivedAt":1,"payload":{"cwd":"/Users/me/dev/ledger"}}"# + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        #expect(h.processor.absorbOutbox(directory: dir) == Outbox.DrainResult(processed: 1))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    /// 메인 context에 저장 안 된 변경이 있으면 먼저 저장한다. 저장하지 못하면 흡수를 미룬다(줄은 그대로).
    @Test func unsavedMainChangesAreSavedFirstOrAbsorbWaits() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (h, card) = try harness()
        try write([("SessionStart", "doc-SessionStart", t0)], to: dir)
        card.title = "고친 제목"
        h.processor.saveContext = { _ in throw SaveFailure.diskUnavailable }
        let waited = h.processor.absorbOutbox(directory: dir)
        #expect(waited == Outbox.DrainResult(processed: 0, skipped: 0, retryPending: true))
        #expect(IntegrationQueue.inspect(directory: dir).count == 1)
        #expect(card.title == "고친 제목")

        h.processor.saveContext = { try $0.save() }
        let absorbed = h.processor.absorbOutbox(directory: dir)
        #expect(absorbed.processed == 1 && !absorbed.retryPending)
        let fresh = ModelContext(h.container)
        #expect(try fresh.fetch(FetchDescriptor<Card>()).first?.title == "고친 제목")
        #expect(try fresh.fetch(FetchDescriptor<Session>()).map(\.id) == [HookHarness.sessionID])
    }
}
