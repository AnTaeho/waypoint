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
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)

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

    @Test func missingDirectoryIsNoop() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-none-\(UUID().uuidString)")
        #expect(Outbox.drain(directory: dir) { _ in } == Outbox.DrainResult())
    }
}
