import Foundation
import Testing
@testable import WaypointKit

@Suite struct CodexUsageTests {
    func tailFixture() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "codex-rollout-tail", withExtension: "jsonl", subdirectory: "Fixtures/usage")
        )
        return try Data(contentsOf: url)
    }

    func line(_ json: String, fallback: Date? = nil) -> UsageGroup? {
        CodexUsage.parseLine(Data(json.utf8), fallbackCapturedAt: fallback)
    }

    /// 실제 기록 끝부분: Codex 줄 뒤에 다른 한도(premium·base_model_inference)와 쓰는 중인 줄이 와도 마지막 Codex 줄을 고른다.
    @Test func latestCodexEventWinsOverOtherLimits() throws {
        let group = try #require(CodexUsage.latest(inTail: try tailFixture(), isPartialStart: false))
        #expect(group.tool == .codex)
        #expect(group.capturedAt == UsageSnapshot.date("2026-10-01T02:23:33.438Z"))
        #expect(group.limits.map(\.label) == ["5시간", "7일"])
        #expect(group.limits.map(\.window.usedPercent) == [95, 39])
        #expect(group.limits[0].window.resetsAt == Date(timeIntervalSince1970: 1_790_836_235))
        #expect(group.limits[1].window.resetsAt == Date(timeIntervalSince1970: 1_791_350_556))
    }

    @Test func partialFirstLineIsDropped() throws {
        let data = try tailFixture()
        // 첫 줄이 잘린 것으로 보면 그 줄은 버리고 나머지에서 찾는다.
        let codexOnlyFirst = Data(#"{"timestamp":"2026-10-01T00:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":1,"window_minutes":300}}}}"#.utf8)
        #expect(CodexUsage.latest(inTail: codexOnlyFirst, isPartialStart: true) == nil)
        #expect(CodexUsage.latest(inTail: codexOnlyFirst, isPartialStart: false) != nil)
        #expect(CodexUsage.latest(inTail: data, isPartialStart: true)?.limits.first?.window.usedPercent == 95)
    }

    @Test func otherLimitIDsAreIgnored() {
        #expect(line(#"{"timestamp":"2026-10-01T00:00:00Z","payload":{"rate_limits":{"limit_id":"base_model_inference","primary":{"used_percent":10,"window_minutes":10080}}}}"#) == nil)
        #expect(line(#"{"timestamp":"2026-10-01T00:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":null,"secondary":null}}}"#) == nil)
        #expect(line(#"{"payload":{"type":"token_count","rate_limits":null}}"#) == nil)
    }

    @Test func missingLimitIDAndThirtyDayWindow() throws {
        let group = try #require(line(#"{"timestamp":"2026-08-17T07:06:49.980Z","payload":{"rate_limits":{"primary":{"used_percent":99.0,"window_minutes":43200,"resets_at":1789372011},"secondary":null}}}"#))
        #expect(group.limits.map(\.label) == ["30일"])
        #expect(group.limits[0].window.percent(at: Date(timeIntervalSince1970: 1_789_000_000)) == 99)
        // 초기화 시각이 지나면 0%
        #expect(group.limits[0].window.percent(at: Date(timeIntervalSince1970: 1_789_372_012)) == 0)
    }

    @Test func limitsSortedByWindowLength() throws {
        let group = try #require(line(#"{"timestamp":"2026-10-01T00:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":12,"window_minutes":10080},"secondary":{"used_percent":40,"window_minutes":300}}}}"#))
        #expect(group.limits.map(\.minutes) == [300, 10080])
    }

    @Test func timestampFallback() {
        let json = #"{"payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":5,"window_minutes":300}}}}"#
        #expect(line(json) == nil)
        #expect(line(json, fallback: Date(timeIntervalSince1970: 7))?.capturedAt == Date(timeIntervalSince1970: 7))
    }

    @Test func sessionsDirectory() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(CodexUsage.sessionsDirectory(environment: [:], home: home).path == "/Users/someone/.codex/sessions")
        #expect(CodexUsage.sessionsDirectory(environment: ["CODEX_HOME": "/tmp/cx"], home: home).path == "/tmp/cx/sessions")
        #expect(CodexUsage.sessionsDirectory(environment: ["CODEX_HOME": ""], home: home).path == "/Users/someone/.codex/sessions")
    }

    /// 최근 날짜 폴더만, 수정 시각이 최근인 순. 가장 최근 파일에 Codex 한도가 없으면 다음 파일에서 찾는다.
    @Test func candidatesAndFallThrough() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        func write(_ folder: String, _ name: String, _ text: String, modified: TimeInterval) throws -> URL {
            let dir = root.appendingPathComponent(folder)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
            return url
        }
        let codex = #"{"timestamp":"2026-09-30T10:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":12,"window_minutes":10080}}}}"#
        let premium = #"{"timestamp":"2026-10-01T10:00:00Z","payload":{"rate_limits":{"limit_id":"premium","primary":null}}}"#
        _ = try write("2026/09/01", "rollout-old.jsonl", codex, modified: 1_000)
        let withCodex = try write("2026/09/30", "rollout-a.jsonl", codex, modified: 2_000)
        let newest = try write("2026/10/01", "rollout-b.jsonl", premium, modified: 3_000)
        _ = try write("2026/10/01", "notes.txt", codex, modified: 4_000)

        let found = CodexUsage.candidates(in: root, days: 2)
        #expect(found.map(\.url.lastPathComponent) == ["rollout-b.jsonl", "rollout-a.jsonl"])
        #expect(found.first?.url.standardizedFileURL == newest.standardizedFileURL)

        let hit = try #require(CodexUsage.latest(in: found))
        #expect(hit.source.url.standardizedFileURL == withCodex.standardizedFileURL)
        #expect(hit.group.limits.first?.window.usedPercent == 12)
        #expect(CodexUsage.candidates(in: root.appendingPathComponent("없음")).isEmpty)
    }

    /// 끝부분 크기보다 큰 파일: 끝에서만 찾고, 거기 없으면 더 크게 읽어 찾는다.
    @Test func largeFileTailRead() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("rollout-\(UUID().uuidString).jsonl")
        defer { try? fm.removeItem(at: url) }
        let codex = #"{"timestamp":"2026-10-01T00:00:00Z","payload":{"rate_limits":{"limit_id":"codex","primary":{"used_percent":33,"window_minutes":300}}}}"#
        let filler = String(repeating: "x", count: CodexUsage.tailSizes[0] + 10)
        let text = codex + "\n" + #"{"payload":{"type":"function_call_output","output":""# + filler + "\"}}\n"
        try Data(text.utf8).write(to: url)
        let candidate = CodexUsage.Candidate(url: url, modified: Date())
        #expect(CodexUsage.load(from: candidate)?.limits.first?.window.usedPercent == 33)
    }
}
