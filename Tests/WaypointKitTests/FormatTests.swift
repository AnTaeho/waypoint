import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct TimeFormatTests {
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

    @Test func elapsed() {
        #expect(TimeFormat.elapsed(from: now - 20, to: now) == "방금")
        #expect(TimeFormat.elapsed(from: now + 60, to: now) == "방금")
        #expect(TimeFormat.elapsed(from: now - minutes(38), to: now) == "38분")
        #expect(TimeFormat.elapsed(from: now - minutes(59.9), to: now) == "59분")
        #expect(TimeFormat.elapsed(from: now - minutes(60), to: now) == "1시간")
        #expect(TimeFormat.elapsed(from: now - minutes(65), to: now) == "1시간 5분")
        #expect(TimeFormat.elapsed(from: now - minutes(27 * 60), to: now) == "1일 3시간")
        #expect(TimeFormat.elapsed(from: now - minutes(48 * 60), to: now) == "2일")
    }

    @Test func relativeWithinToday() {
        #expect(TimeFormat.relative(now - 30, now: now, calendar: calendar) == "방금")
        #expect(TimeFormat.relative(now + 120, now: now, calendar: calendar) == "방금")
        #expect(TimeFormat.relative(now - minutes(22), now: now, calendar: calendar) == "22분 전")
        #expect(TimeFormat.relative(at(9, 28, 7, 10), now: now, calendar: calendar) == "3시간 전")
    }

    @Test func relativeYesterdayAndDays() {
        #expect(TimeFormat.relative(at(9, 27, 23, 12), now: now, calendar: calendar) == "어제 23:12")
        #expect(TimeFormat.relative(at(9, 27, 8, 5), now: now, calendar: calendar) == "어제 08:05")
        #expect(TimeFormat.relative(at(9, 25, 12, 0), now: now, calendar: calendar) == "3일 전")
        #expect(TimeFormat.relative(at(9, 22, 12, 0), now: now, calendar: calendar) == "6일 전")
        #expect(TimeFormat.relative(at(9, 21, 12, 0), now: now, calendar: calendar) == "9월 21일")
        #expect(TimeFormat.relative(at(12, 24, 12, 0, year: 2025), now: now, calendar: calendar) == "2025년 12월 24일")
    }

    @Test func timestampWithSeconds() {
        let a = at(9, 28, 9, 12) + 16
        #expect(TimeFormat.timestamp(a, now: now, calendar: calendar) == "09:12")
        #expect(TimeFormat.timestamp(a, now: now, seconds: true, calendar: calendar) == "09:12:16")
        #expect(TimeFormat.timestamp(a + 5, now: now, seconds: true, calendar: calendar) == "09:12:21")
        #expect(TimeFormat.timestamp(at(9, 27, 23, 5) + 3, now: now, seconds: true, calendar: calendar) == "어제 23:05:03")
    }

    @Test func minutesWinAcrossMidnight() {
        let justAfterMidnight = at(9, 28, 0, 10)
        #expect(TimeFormat.relative(at(9, 27, 23, 50), now: justAfterMidnight, calendar: calendar) == "20분 전")
        #expect(TimeFormat.relative(at(9, 27, 22, 0), now: justAfterMidnight, calendar: calendar) == "어제 22:00")
    }

    @Test func dayBoundaryFollowsTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 서울 09-28 10:30 = UTC 09-28 01:30, 서울 09-27 23:12 = UTC 09-27 14:12 → 둘 다 「어제」
        #expect(TimeFormat.relative(at(9, 27, 23, 12), now: now, calendar: utc) == "어제 14:12")
        // 서울 09-28 08:00 = UTC 09-27 23:00 → UTC 기준으론 어제
        #expect(TimeFormat.relative(at(9, 28, 8, 0), now: now, calendar: calendar) == "2시간 전")
        #expect(TimeFormat.relative(at(9, 28, 8, 0), now: now, calendar: utc) == "어제 23:00")
    }
}

@Suite struct SessionFormatTests {
    @Test func labels() {
        #expect(SessionFormat.label(kind: .main, id: "7f2a9c41-3e8b", agentName: nil) == "sess·7f2a")
        #expect(SessionFormat.label(kind: .subagent, id: "3b6d8f0a", agentName: "test-writer") == "↳ test-writer")
        #expect(SessionFormat.label(kind: .subagent, id: "3b6d8f0a", agentName: nil) == "sess·3b6d")
        #expect(SessionFormat.label(kind: .main, id: "ab", agentName: nil) == "sess·ab")
    }

    @Test func recentFileIsLatestForThatSession() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let s1 = makeSession(ctx, p, id: "s1")
        let s2 = makeSession(ctx, p, id: "s2")
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        #expect(SessionFormat.recentFileName(card: card, session: s1) == nil)
        Event.record(.fileChanged, in: ctx, card: card, session: s1, at: t0 + 60, payload: ["path": "A/Old.swift"])
        Event.record(.fileChanged, in: ctx, card: card, session: s1, at: t0 + 120, payload: ["path": "A/New.swift"])
        Event.record(.fileChanged, in: ctx, card: card, session: s2, at: t0 + 180, payload: ["path": "B/Other.swift"])
        #expect(SessionFormat.recentFileName(card: card, session: s1) == "New.swift")
        #expect(SessionFormat.recentFileName(card: card, session: s2) == "Other.swift")
    }
}

@Suite struct RecentEventFormatTests {
    @Test func statusLines() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "7f2a9c41")
        let card = p.makeCard(in: ctx, title: "영수증", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0 + 60, in: ctx)
        try CardLifecycle.move(card, to: .done, at: t0 + 120, in: ctx)
        try CardLifecycle.move(card, to: .archived, at: t0 + 180, in: ctx)

        CardLifecycle.detach(card, s, at: t0 + 240, in: ctx)
        try CardLifecycle.move(card, to: .next, at: t0 + 300, in: ctx)
        try CardLifecycle.move(card, to: .idea, at: t0 + 360, in: ctx)

        // 보관·다음·아이디어로 바뀐 것은 뺀다.
        let lines = RecentEventFormat.lines(from: card.events ?? [], now: t0 + 400)
        #expect(lines.map(\.text) == ["완료", "작업중"])
        #expect(lines.map(\.marker) == [.done, .active])
        #expect(lines.allSatisfy { $0.subject == "LDG-1" && $0.subjectIsCardID })
        #expect(lines[1].detail == "sess·7f2a")
        #expect(lines[0].detail == nil)
    }

    @Test func createdCommitAndGuideLines() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let idea = p.makeCard(in: ctx, title: "CSV 내보내기", kind: .idea, status: .idea, at: t0)
        let task = p.makeCard(in: ctx, title: "파서 테스트", status: .next, at: t0)
        let e1 = Event.record(.cardCreated, in: ctx, card: idea, at: t0, payload: ["status": "idea"])
        let e2 = Event.record(.cardCreated, in: ctx, card: task, at: t0, payload: ["status": "next"])
        let e3 = Event.record(.commit, in: ctx, card: task, at: t0, payload: ["hash": "a91c3e2f00", "message": "m"])
        let e4 = Event.record(.guideSynced, in: ctx, project: p, at: t0, payload: ["relPath": "docs/CLAUDE.md"])

        #expect(RecentEventFormat.line(for: e1)?.text == "아이디어 · CSV 내보내기")
        #expect(RecentEventFormat.line(for: e1)?.marker == .idea)
        #expect(RecentEventFormat.line(for: e2)?.text == "새 카드 · 파서 테스트")
        #expect(RecentEventFormat.line(for: e3)?.text == "커밋 a91c3e2")
        let guide = try #require(RecentEventFormat.line(for: e4))
        #expect(guide.text == "CLAUDE.md 바뀜")
        #expect(guide.subject == "가계부 앱")
        #expect(guide.subjectIsCardID == false)
        #expect(guide.marker == .guide)
    }

    @Test func hiddenTypesAndLimit() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "s")
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let hidden: [Event] = [
            Event.record(.sessionStart, in: ctx, project: p, session: s, at: t0),
            Event.record(.sessionEnd, in: ctx, project: p, session: s, at: t0),
            Event.record(.fileChanged, in: ctx, card: card, session: s, at: t0, payload: ["path": "x"]),
            Event.record(.cardAttached, in: ctx, card: card, session: s, at: t0),
            Event.record(.cardDetached, in: ctx, card: card, session: s, at: t0),
        ]
        #expect(hidden.allSatisfy { RecentEventFormat.line(for: $0) == nil })

        let many = (0..<30).map { i in
            Event.record(.commit, in: ctx, card: card, at: t0 + Double(i), payload: ["hash": .string("h\(i)")])
        }
        let lines = RecentEventFormat.lines(from: hidden + many, now: t0 + 60)
        #expect(lines.count == RecentEventFormat.defaultLimit)
        #expect(lines.count == 15)
        #expect(lines.first?.text == "커밋 h29")
    }

    @Test func archivedProjectIsLeftOut() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let e = Event.record(.commit, in: ctx, card: card, at: t0, payload: ["hash": "abc"])
        p.archivedAt = t0
        #expect(RecentEventFormat.lines(from: [e], now: t0).isEmpty)
    }

    @Test func olderThanSevenDaysIsLeftOut() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let week: TimeInterval = 7 * 24 * 3600
        let old = Event.record(.commit, in: ctx, card: card, at: t0 - week - 1, payload: ["hash": "old"])
        let edge = Event.record(.commit, in: ctx, card: card, at: t0 - week, payload: ["hash": "edge"])
        let lines = RecentEventFormat.lines(from: [old, edge], now: t0)
        #expect(lines.map(\.text) == ["커밋 edge"])
    }

    @Test func sampleSceneHasDesignLines() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let now = t0 + 7 * 24 * 3600
        try SampleData.seedIfEmpty(ctx, now: now)
        let events = try ctx.fetch(FetchDescriptor<Event>())
        let lines = RecentEventFormat.lines(from: events, now: now)
        let texts = lines.map { "\($0.subject ?? "") \($0.text)" }
        #expect(texts.contains("LDG-16 작업중"))
        #expect(texts.contains("LDG-14 작업중"))
        #expect(texts.contains("LDG-21 아이디어 · 거래 내역 CSV 내보내기"))
        #expect(lines.first { $0.subject == "LDG-16" }?.detail == "↳ test-writer")
    }
}
