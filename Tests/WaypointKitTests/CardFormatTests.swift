import Foundation
import Testing
@testable import WaypointKit

@Suite struct CardFormatTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// 서울 기준 2026-09-28 10:30
    var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10, minute: 30))!
    }

    func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func dayAndTimestamp() {
        #expect(TimeFormat.day(at(9, 28, 0, 5), now: now, calendar: calendar) == "오늘")
        #expect(TimeFormat.day(now + 3600, now: now, calendar: calendar) == "오늘")
        #expect(TimeFormat.day(at(9, 27, 23, 59), now: now, calendar: calendar) == "어제")
        #expect(TimeFormat.day(at(9, 24, 12, 0), now: now, calendar: calendar) == "9월 24일")
        #expect(TimeFormat.day(at(12, 24, 12, 0, year: 2025), now: now, calendar: calendar) == "2025년 12월 24일")
        #expect(TimeFormat.timestamp(at(9, 28, 9, 5), now: now, calendar: calendar) == "09:05")
        #expect(TimeFormat.timestamp(at(9, 27, 14, 22), now: now, calendar: calendar) == "어제 14:22")
        #expect(TimeFormat.timestamp(at(9, 26, 22, 40), now: now, calendar: calendar) == "9월 26일 22:40")
    }

    @Test func workTime() {
        let start = now - minutes(38)
        #expect(CardFormat.workTime(state: .live, attachedAt: start, lastSeenAt: now, now: now) == "38분째")
        #expect(CardFormat.workTime(state: .live, attachedAt: now - 10, lastSeenAt: now, now: now) == "방금")
        #expect(CardFormat.workTime(state: .stalled, attachedAt: start, lastSeenAt: now - minutes(22), now: now) == "멈춤 22분")
        #expect(CardFormat.workTime(state: .none, attachedAt: start, lastSeenAt: now, now: now) == nil)
    }

    @Test func doneLineAndTotals() {
        let stats = CardWorkStats(sessionCount: 2, subagentCount: 0, commitCount: 3)
        #expect(CardFormat.doneLine(doneAt: at(9, 27, 9, 0), stats: stats, now: now, calendar: calendar)
                == "어제 · 세션 2회 · 커밋 3")
        let noCommit = CardWorkStats(sessionCount: 3, subagentCount: 0, commitCount: 0)
        #expect(CardFormat.doneLine(doneAt: at(9, 24, 9, 0), stats: noCommit, now: now, calendar: calendar)
                == "9월 24일 · 세션 3회")
        let none = CardWorkStats(sessionCount: 0, subagentCount: 0, commitCount: 0)
        #expect(CardFormat.doneLine(doneAt: nil, stats: none, now: now, calendar: calendar) == "")
        #expect(CardFormat.workTotal(CardWorkStats(sessionCount: 1, subagentCount: 1, commitCount: 0)) == "세션 1회 · 서브에이전트 1")
        #expect(CardFormat.workTotal(none) == "없음")
        #expect(CardFormat.lineDelta(added: 84, removed: 12) == "+84 −12")
    }

    @Test func originLine() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let a = p.makeCard(in: ctx, title: "a", origin: .claude, at: at(9, 27, 22, 0))
        let b = p.makeCard(in: ctx, title: "b", at: at(9, 20, 9, 0))
        #expect(CardFormat.originLine(a, now: now, calendar: calendar) == "Claude · 어제")
        #expect(CardFormat.originLine(b, now: now, calendar: calendar) == "직접 작성 · 9월 20일")
    }
}
