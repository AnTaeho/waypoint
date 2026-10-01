import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct OutboxTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-outbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 훅 스크립트와 같은 꼴의 한 줄
    private func line(_ event: String, _ fixtureName: String, at date: Date) throws -> String {
        let payload = String(decoding: try fixture(fixtureName), as: UTF8.self).replacingOccurrences(of: "\n", with: "")
        return #"{"event":"\#(event)","receivedAt":\#(Int(date.timeIntervalSince1970)),"payload":\#(payload)}"#
    }

    @Test func parseLine() throws {
        let entry = try #require(Outbox.parse(line: Substring(try line("SessionStart", "doc-SessionStart", at: t0))))
        #expect(entry.event == "SessionStart")
        #expect(entry.receivedAt == Date(timeIntervalSince1970: Double(Int(t0.timeIntervalSince1970))))
        #expect(HookInput(event: entry.event, json: entry.payload)?.source == "startup")
        #expect(Outbox.parse(line: "not json") == nil)
        #expect(Outbox.parse(line: #"{"event":"Stop","receivedAt":1}"#) == nil)
    }

    @Test func parseClaudePid() throws {
        let payload = String(decoding: try fixture("doc-Stop"), as: UTF8.self).replacingOccurrences(of: "\n", with: "")
        let withPid = #"{"event":"Stop","receivedAt":100,"claudePid":5287,"payload":\#(payload)}"#
        let entry = try #require(Outbox.parse(line: Substring(withPid)))
        #expect(entry.claudePid == 5287)
        #expect(HookInput(event: entry.event, json: entry.payload)?.sessionID == HookHarness.sessionID)
        #expect(try #require(Outbox.parse(line: Substring(try line("Stop", "doc-Stop", at: t0)))).claudePid == nil)
        let bad = #"{"event":"Stop","receivedAt":100,"claudePid":"x","payload":\#(payload)}"#
        #expect(try #require(Outbox.parse(line: Substring(bad))).claudePid == nil)

        // 흡수하면 메인 세션에 PID가 적힌다
        let h = try HookHarness()
        h.processor.handle(entry)
        #expect(try h.session()?.claudePid == 5287)
    }

    @Test func drainAppliesInOrderAndEmpties() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let lines = [
            try line("SessionStart", "doc-SessionStart", at: start),
            try line("UserPromptSubmit", "doc-UserPromptSubmit", at: start + 60),
            "깨진 줄",
            try line("SessionEnd", "doc-SessionEnd", at: start + 600),
        ]
        try (lines.joined(separator: "\n") + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8
        )

        let h = try HookHarness()
        var events: [String] = []
        let result = Outbox.drain(directory: dir) { entry in
            events.append(entry.event)
            h.processor.handle(entry)
        }
        #expect(result == Outbox.DrainResult(processed: 3, skipped: 1))
        #expect(events == ["SessionStart", "UserPromptSubmit", "SessionEnd"])
        let s = try #require(try h.session())
        #expect(s.startedAt == start)
        #expect(s.endedAt == start + 600)
        // 깨진 줄은 버리지 않고 격리 파일에 원문 그대로 남는다
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [Outbox.quarantineFileName])
        #expect(try quarantined(dir) == ["깨진 줄"])

        // 두 번째 흡수는 할 일이 없다
        #expect(Outbox.drain(directory: dir) { _ in } == Outbox.DrainResult())
    }

    @Test func leftoverClaimedFileIsProcessedFirst() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        try (try line("SessionStart", "doc-SessionStart", at: start) + "\n").write(
            to: dir.appendingPathComponent("outbox.processing-0000000000001-a.jsonl"), atomically: true, encoding: .utf8
        )
        try (try line("SessionEnd", "doc-SessionEnd", at: start + 60) + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8
        )
        var events: [String] = []
        Outbox.drain(directory: dir) { events.append($0.event) }
        #expect(events == ["SessionStart", "SessionEnd"])
    }

    private enum SaveFailure: Error { case diskUnavailable }

    @Test func failedSavePreservesSuffixAndStopsBeforeLaterFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("outbox.processing-0000000000001-a.jsonl")
        let later = dir.appendingPathComponent("outbox.processing-0000000000002-b.jsonl")
        let start = try line("SessionStart", "doc-SessionStart", at: t0)
        let prompt = try line("UserPromptSubmit", "doc-UserPromptSubmit", at: t0 + 1)
        let stop = try line("Stop", "doc-Stop", at: t0 + 2)
        let end = try line("SessionEnd", "doc-SessionEnd", at: t0 + 3)
        try ([start, prompt, stop].joined(separator: "\n") + "\n").write(to: first, atomically: true, encoding: .utf8)
        try (end + "\n").write(to: later, atomically: true, encoding: .utf8)
        var attempted: [String] = []
        var saved: [String] = []
        let failed = Outbox.drain(directory: dir) { entry in
            attempted.append(entry.event)
            if entry.event == "UserPromptSubmit" { throw SaveFailure.diskUnavailable }
            saved.append(entry.event)
        }
        #expect(failed.processed == 1 && failed.skipped == 0 && failed.retryPending)
        #expect(attempted == ["SessionStart", "UserPromptSubmit"])
        #expect(try String(contentsOf: first, encoding: .utf8) == prompt + "\n" + stop + "\n")
        #expect(try String(contentsOf: later, encoding: .utf8) == end + "\n")
        let recovered = Outbox.drain(directory: dir) { saved.append($0.event) }
        #expect(recovered.processed == 3 && !recovered.retryPending)
        #expect(saved == ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test(arguments: AgentProvider.allCases)
    func repeatedFailureKeepsFirstEntryUntilRecovery(provider: AgentProvider) throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let raw = try line("SessionStart", "doc-SessionStart", at: t0)
        var object = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        object["provider"] = provider.rawValue
        let encoded = try JSONSerialization.data(withJSONObject: object)
        try (String(decoding: encoded, as: UTF8.self) + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        for _ in 0..<2 {
            let result = Outbox.drain(directory: dir) { _ in throw SaveFailure.diskUnavailable }
            #expect(result.processed == 0 && result.retryPending)
            #expect(IntegrationQueue.inspect(directory: dir).count == 1)
        }
        var received: [AgentProvider] = []
        let recovered = Outbox.drain(directory: dir) { received.append($0.provider) }
        #expect(recovered.processed == 1 && !recovered.retryPending && received == [provider])
        #expect(IntegrationQueue.inspect(directory: dir).count == 0)
    }

    private func quarantined(_ dir: URL) throws -> [String] {
        let text = try String(contentsOf: dir.appendingPathComponent(Outbox.quarantineFileName), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    @Test func corruptLineIsQuarantinedVerbatimAndNotCountedAsPending() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let broken = #"{"event":"Stop","receivedAt":1,"payload":"#
        let unknown = #"{"event":"Stop","receivedAt":1,"provider":"other","payload":{}}"#
        let start = try line("SessionStart", "doc-SessionStart", at: t0)
        try ([broken, start, unknown].joined(separator: "\n") + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        var events: [String] = []
        let result = Outbox.drain(directory: dir) { events.append($0.event) }
        #expect(result == Outbox.DrainResult(processed: 1, skipped: 2))
        #expect(events == ["SessionStart"])
        #expect(try quarantined(dir) == [broken, unknown])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: dir.appendingPathComponent(Outbox.quarantineFileName).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(IntegrationQueue.inspect(directory: dir) == IntegrationQueue())
        // 격리 파일은 다시 흡수하지 않는다
        #expect(Outbox.drain(directory: dir) { _ in Issue.record("격리 줄을 다시 읽음") } == Outbox.DrainResult())
        #expect(try quarantined(dir) == [broken, unknown])
    }

    @Test func corruptLinesAroundFailedSaveAreQuarantinedOnce() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = try line("SessionStart", "doc-SessionStart", at: t0)
        let prompt = try line("UserPromptSubmit", "doc-UserPromptSubmit", at: t0 + 1)
        let end = try line("SessionEnd", "doc-SessionEnd", at: t0 + 2)
        try (["앞 깨진 줄", start, prompt, "뒤 깨진 줄", end].joined(separator: "\n") + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        var saved: [String] = []
        let failed = Outbox.drain(directory: dir) { entry in
            if entry.event == "UserPromptSubmit" { throw SaveFailure.diskUnavailable }
            saved.append(entry.event)
        }
        #expect(failed.processed == 1 && failed.skipped == 1 && failed.retryPending)
        #expect(try quarantined(dir) == ["앞 깨진 줄"])
        #expect(IntegrationQueue.inspect(directory: dir).count == 3)
        let recovered = Outbox.drain(directory: dir) { saved.append($0.event) }
        #expect(recovered == Outbox.DrainResult(processed: 2, skipped: 1))
        #expect(saved == ["SessionStart", "UserPromptSubmit", "SessionEnd"])
        #expect(try quarantined(dir) == ["앞 깨진 줄", "뒤 깨진 줄"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == [Outbox.quarantineFileName])
    }

    @Test func quarantineWriteFailureKeepsLineForRetry() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 격리 파일 자리에 폴더가 있으면 덧붙이지 못한다
        let blocker = dir.appendingPathComponent(Outbox.quarantineFileName)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
        let start = try line("SessionStart", "doc-SessionStart", at: t0)
        try (["깨진 줄", start].joined(separator: "\n") + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        let failed = Outbox.drain(directory: dir) { _ in Issue.record("깨진 줄 뒤를 먼저 처리함") }
        #expect(failed == Outbox.DrainResult(processed: 0, skipped: 0, retryPending: true))
        #expect(IntegrationQueue.inspect(directory: dir).count == 2)
        try FileManager.default.removeItem(at: blocker)
        var events: [String] = []
        #expect(Outbox.drain(directory: dir) { events.append($0.event) } == Outbox.DrainResult(processed: 1, skipped: 1))
        #expect(events == ["SessionStart"])
        #expect(try quarantined(dir) == ["깨진 줄"])
    }

    /// 저장 실패로 되돌린 줄을 다시 처리해도 서브에이전트 대기 항목이 겹치거나 사라지지 않는다.
    @Test func retriedSubagentLinesKeepPendingSpawnConsistent() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = try HookHarness()
        h.project.nextCardNumber = 16
        let card = h.project.makeCard(in: h.context, title: "파서 단위 테스트", status: .next, at: t0)
        try #require(card.number == 16)
        let lines = [try line("SessionStart", "doc-SessionStart", at: t0),
                     try line("PreToolUse", "doc-PreToolUse-Agent", at: t0 + 10),
                     try line("SubagentStart", "doc-SubagentStart", at: t0 + 11)]
        try (lines.joined(separator: "\n") + "\n").write(
            to: dir.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        var failing: Set<String> = ["PreToolUse", "SubagentStart"]
        let apply: (Outbox.Entry) throws -> Void = { entry in
            h.processor.saveContext = { context in
                if failing.remove(entry.event) != nil { throw SaveFailure.diskUnavailable }
                try context.save()
            }
            h.processor.handle(entry)
            if h.processor.lastSaveFailed { throw SaveFailure.diskUnavailable }
        }
        #expect(Outbox.drain(directory: dir, handle: apply).retryPending)
        #expect(h.processor.pendingSpawns[HookHarness.sessionID, default: []].isEmpty)
        #expect(Outbox.drain(directory: dir, handle: apply).retryPending)
        #expect(h.processor.pendingSpawns[HookHarness.sessionID]?.count == 1)
        #expect(try h.session(HookHarness.agentID) == nil)
        let recovered = Outbox.drain(directory: dir, handle: apply)
        #expect(recovered.processed == 1 && !recovered.retryPending)
        let sub = try #require(try h.session(HookHarness.agentID))
        #expect(sub.agentName == "test-writer")
        #expect(card.openCardSessions.contains { $0.session === sub })
        // SwiftData rollback은 메모리의 모델 값을 되돌리지 않는다. 실패한 SubagentStart가 붙인 연결이 기본값만 남은 채
        // 카드 관계에 남았다가 재시도 저장 때 함께 들어간다(세션 id "", 연결 session nil). DECISIONS 2026-10-01 참고.
        let sessions = try h.context.fetchCount(FetchDescriptor<Session>())
        withKnownIssue("rollback 뒤 남은 모델이 재시도 저장에 섞인다") {
            #expect(card.openCardSessions.count == 1)
            #expect(sessions == 2)
        }
        #expect(h.processor.pendingSpawns[HookHarness.sessionID, default: []].isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func missingDirectoryIsNoop() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-none-\(UUID().uuidString)")
        #expect(Outbox.drain(directory: dir) { _ in } == Outbox.DrainResult())
    }
}
