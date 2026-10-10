import Foundation
import Testing
@testable import WaypointKit

@Suite struct SessionStatusSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func parse(_ json: String) -> SessionStatusSnapshot {
        SessionStatusSnapshot.parse(Data(json.utf8))
    }

    func line(context: Double?, age: TimeInterval = 0, name: String? = nil) -> SessionStatusLine? {
        let entry = SessionStatusSnapshot.Entry(name: name, context: context, at: now.addingTimeInterval(-age))
        return SessionStatusSnapshot(entries: ["s": entry]).lines(now: now)["s"]
    }

    @Test func tapFormat() {
        let s = parse("""
            {"aaaa-1111":{"at":1790000000,"name":"결제 영수증 고치기","context":62.5},
             "bbbb-2222":{"at":1789999000,"context":91},"cccc-3333":{"at":1790000000,"name":"이름만"}}
            """)
        #expect(s.entries.count == 3)
        #expect(s.entries["aaaa-1111"] == .init(name: "결제 영수증 고치기", context: 62.5,
                                                at: Date(timeIntervalSince1970: 1_790_000_000)))
        #expect(s.entries["bbbb-2222"] == .init(context: 91, at: Date(timeIntervalSince1970: 1_789_999_000)))
        #expect(s.entries["cccc-3333"]?.context == nil)
    }

    @Test func skipsUnreadableContentAndEntries() {
        #expect(parse("not json").entries.isEmpty)
        #expect(parse("[1,2]").entries.isEmpty)
        #expect(parse("{}").entries.isEmpty)
        let s = parse("""
            {"a":"x","b":{"at":1790000000},"c":{"at":1790000000,"name":"  ","context":true},
             "":{"name":"빈 ID"},"d":{"name":7,"context":"41.5"}}
            """)
        #expect(Array(s.entries.keys) == ["d"])
        #expect(s.entries["d"] == .init(name: nil, context: 41.5, at: nil))
    }

    @Test func nameBecomesOneLine() {
        #expect(parse(#"{"a":{"name":"  첫 줄\n둘째   줄 "}}"#).entries["a"]?.name == "첫 줄 둘째 줄")
    }

    @Test func loadReadsFileAndMissingFileIsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(SessionStatusSnapshot.fileName)
        #expect(SessionStatusSnapshot.load(from: url).entries.isEmpty)
        try Data(#"{"a":{"at":1790000000,"name":"이름"}}"#.utf8).write(to: url)
        #expect(SessionStatusSnapshot.load(from: url).entries["a"]?.name == "이름")
        #expect(url.lastPathComponent == "session-status.json")
    }

    @Test func contextRoundsAndClamps() {
        #expect(line(context: 62.5)?.contextPercent == 63)
        #expect(line(context: 62.4)?.contextPercent == 62)
        #expect(line(context: 0)?.contextPercent == 0)
        #expect(line(context: -3)?.contextPercent == 0)
        #expect(line(context: 140)?.contextPercent == 100)
    }

    @Test func staleContextIsHiddenButNameStays() {
        let limit = SessionStatusSnapshot.contextStaleAfter
        #expect(limit == 3 * 60 * 60)
        #expect(line(context: 50, age: limit)?.contextPercent == 50)
        #expect(line(context: 50, age: limit + 1) == nil)
        #expect(line(context: 50, age: limit + 1, name: "이름") == SessionStatusLine(name: "이름", contextPercent: nil))
        // 시각이 없는 항목도 사용률은 숨긴다
        let noTime = SessionStatusSnapshot(entries: ["s": .init(name: "이름", context: 50, at: nil)])
        #expect(noTime.lines(now: now)["s"] == SessionStatusLine(name: "이름", contextPercent: nil))
        #expect(SessionStatusSnapshot(entries: ["s": .init(context: 50, at: nil)]).lines(now: now).isEmpty)
    }

    @Test func contextTextAndHighMark() {
        #expect(SessionStatusLine(contextPercent: 62).contextText == "컨텍스트 62%")
        #expect(SessionStatusLine(contextPercent: 0).contextText == "컨텍스트 0%")
        #expect(SessionStatusLine(name: "이름").contextText == nil)
        #expect(SessionStatusLine.highContextPercent == 80)
        #expect(!SessionStatusLine(contextPercent: 79).isContextHigh)
        #expect(SessionStatusLine(contextPercent: 80).isContextHigh)
        #expect(!SessionStatusLine.none.isContextHigh)
        // 79.5는 80으로 올라가 진하게 보인다
        #expect(line(context: 79.5)?.isContextHigh == true)
        #expect(line(context: 79.4)?.isContextHigh == false)
    }

    @Test func labelPrefersName() {
        #expect(SessionStatusLine(name: "결제 고치기").label(fallback: "sess·7f2a") == "결제 고치기")
        #expect(SessionStatusLine.none.label(fallback: "sess·7f2a") == "sess·7f2a")
        #expect(SessionStatusLine(contextPercent: 10).label(fallback: "sess·7f2a") == "sess·7f2a")
    }
}
