import Foundation
import Testing
@testable import WaypointKit

@Suite struct UsageSnapshotTests {
    func parse(_ json: String, fallback: Date? = nil) -> UsageSnapshot? {
        UsageSnapshot.parse(Data(json.utf8), fallbackCapturedAt: fallback)
    }

    @Test func tapFormat() throws {
        let s = try #require(parse("""
            {"capturedAt":1790000000,"rateLimits":{"five_hour":{"used_percentage":42.5,"resets_at":1790003600},
             "seven_day":{"used_percentage":18,"resets_at":1790500000}}}
            """))
        #expect(s.capturedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(s.fiveHour == .init(usedPercent: 42.5, resetsAt: Date(timeIntervalSince1970: 1_790_003_600)))
        #expect(s.sevenDay == .init(usedPercent: 18, resetsAt: Date(timeIntervalSince1970: 1_790_500_000)))
    }

    @Test func numbersAsStringsAndMilliseconds() throws {
        let s = try #require(parse("""
            {"capturedAt":"1790000000","rateLimits":{"five_hour":{"used_percentage":"7.5","resets_at":1790003600000}}}
            """))
        #expect(s.fiveHour?.usedPercent == 7.5)
        #expect(s.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_790_003_600))
        #expect(s.sevenDay == nil)
        #expect(s.capturedAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func isoResetTimes() throws {
        let s = try #require(parse("""
            {"capturedAt":1790000000,"rateLimits":{
             "five_hour":{"used_percentage":1,"resets_at":"2026-09-28T06:20:00Z"},
             "seven_day":{"used_percentage":2,"resets_at":"2026-10-02T06:20:00.500Z"}}}
            """))
        #expect(s.fiveHour?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-28T06:20:00Z"))
        #expect(s.sevenDay?.resetsAt?.timeIntervalSince1970 == ISO8601DateFormatter().date(from: "2026-10-02T06:20:00Z")!.timeIntervalSince1970 + 0.5)
    }

    @Test func missingOrBadResetTime() throws {
        let s = try #require(parse("""
            {"capturedAt":1790000000,"rateLimits":{"five_hour":{"used_percentage":3},
             "seven_day":{"used_percentage":4,"resets_at":"다음 주"}}}
            """))
        #expect(s.fiveHour?.resetsAt == nil)
        #expect(s.sevenDay?.resetsAt == nil)
    }

    @Test func rawRateLimitsObject() throws {
        let s = try #require(parse(#"{"five_hour":{"used_percentage":10}}"#, fallback: Date(timeIntervalSince1970: 5)))
        #expect(s.fiveHour?.usedPercent == 10)
        #expect(s.capturedAt == Date(timeIntervalSince1970: 5))
    }

    @Test func capturedAtFallback() {
        let json = #"{"rateLimits":{"five_hour":{"used_percentage":10}}}"#
        #expect(parse(json) == nil)
        #expect(parse(json, fallback: Date(timeIntervalSince1970: 9))?.capturedAt == Date(timeIntervalSince1970: 9))
    }

    @Test func rejects() {
        #expect(parse("") == nil)
        #expect(parse("[]") == nil)
        #expect(parse("not json") == nil)
        #expect(parse(#"{"capturedAt":1,"rateLimits":{}}"#) == nil)
        #expect(parse(#"{"capturedAt":1,"rateLimits":{"five_hour":{"used_percentage":true}}}"#) == nil)
        #expect(parse(#"{"capturedAt":1,"rateLimits":{"five_hour":{"used_percentage":"많이"}}}"#) == nil)
        #expect(parse(#"{"capturedAt":1,"rateLimits":{"five_hour":{}}}"#) == nil)
        #expect(parse(#"{"capturedAt":1,"rateLimits":{"five_hour":null}}"#) == nil)
    }

    @Test func percentRoundsClampsAndResets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UsageSnapshot.Window(usedPercent: 41.6, resetsAt: nil).percent(at: now) == 42)
        #expect(UsageSnapshot.Window(usedPercent: 130, resetsAt: nil).percent(at: now) == 100)
        #expect(UsageSnapshot.Window(usedPercent: -3, resetsAt: nil).percent(at: now) == 0)
        #expect(UsageSnapshot.Window(usedPercent: 50, resetsAt: nil).fraction(at: now) == 0.5)
        let passed = UsageSnapshot.Window(usedPercent: 80, resetsAt: now - 1)
        #expect(passed.percent(at: now) == 0)
        #expect(passed.fraction(at: now) == 0)
        #expect(UsageSnapshot.Window(usedPercent: 80, resetsAt: now + 1).percent(at: now) == 80)
    }

    @Test func staleness() {
        let captured = Date(timeIntervalSince1970: 1_000_000)
        let s = UsageSnapshot(fiveHour: .init(usedPercent: 1, resetsAt: nil), sevenDay: nil, capturedAt: captured)
        #expect(!s.isStale(now: captured + minutes(30)))
        #expect(s.isStale(now: captured + minutes(31)))
    }

    @Test func loadUsesModificationDateWhenNoCapturedAt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(UsageSnapshot.fileName)
        #expect(UsageSnapshot.load(from: url) == nil)
        try Data(#"{"rateLimits":{"seven_day":{"used_percentage":18}}}"#.utf8).write(to: url)
        let modified = Date(timeIntervalSince1970: 1_790_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let s = try #require(UsageSnapshot.load(from: url))
        #expect(s.capturedAt == modified)
        #expect(s.sevenDay?.usedPercent == 18)
    }
}

@Suite struct UsageFormatTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// 서울 기준 2026-09-28 10:30
    var now: Date { at(9, 28, 10, 30) }

    func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func menuLine() {
        let both = UsageSnapshot(
            fiveHour: .init(usedPercent: 41.6, resetsAt: nil),
            sevenDay: .init(usedPercent: 18, resetsAt: nil),
            capturedAt: now
        )
        #expect(UsageFormat.menuLine(both, now: now) == "사용량 5시간 42% · 7일 18%")
        let weekOnly = UsageSnapshot(fiveHour: nil, sevenDay: .init(usedPercent: 3, resetsAt: nil), capturedAt: now)
        #expect(UsageFormat.menuLine(weekOnly, now: now) == "사용량 7일 3%")
    }

    @Test func resetTime() {
        #expect(UsageFormat.resetTime(at(9, 28, 15, 20), now: now, calendar: calendar) == "오후 3:20")
        #expect(UsageFormat.resetTime(at(9, 28, 0, 5), now: now, calendar: calendar) == "오전 12:05")
        #expect(UsageFormat.resetTime(at(9, 28, 12, 0), now: now, calendar: calendar) == "오후 12:00")
        #expect(UsageFormat.resetTime(at(9, 29, 9, 0), now: now, calendar: calendar) == "내일 오전 9:00")
        #expect(UsageFormat.resetTime(at(10, 2, 15, 20), now: now, calendar: calendar) == "10월 2일 오후 3:20")
    }

    @Test func help() {
        let window = UsageSnapshot.Window(usedPercent: 42, resetsAt: at(9, 28, 15, 20))
        #expect(UsageFormat.help(window, capturedAt: now - minutes(2), now: now, calendar: calendar) == "오후 3:20에 초기화")
        #expect(
            UsageFormat.help(window, capturedAt: now - minutes(45), now: now, calendar: calendar)
                == "오후 3:20에 초기화 · 45분 전 기준"
        )
        let noReset = UsageSnapshot.Window(usedPercent: 42, resetsAt: nil)
        #expect(UsageFormat.help(noReset, capturedAt: now, now: now, calendar: calendar) == nil)
        let passed = UsageSnapshot.Window(usedPercent: 42, resetsAt: now - 60)
        #expect(UsageFormat.help(passed, capturedAt: now - minutes(40), now: now, calendar: calendar) == "40분 전 기준")
    }
}
