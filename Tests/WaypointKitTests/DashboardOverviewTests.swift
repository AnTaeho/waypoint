import Foundation
import Testing
@testable import WaypointKit

@Suite struct DashboardOverviewTests {
    @Test func countsLiveAndStalledRowsIncludingCardlessAndSubagent() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let now = t0 + minutes(30)
        let main = makeSession(ctx, p, id: "main", lastSeenAt: now)
        let sub = makeSession(ctx, p, id: "sub", lastSeenAt: now, parent: main)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "child", at: t0), sub, at: t0, in: ctx)
        _ = makeSession(ctx, p, id: "stalled", lastSeenAt: t0)
        _ = p.makeCard(in: ctx, title: "next", status: .next, at: t0)
        let result = DashboardOverview(projects: [p], now: now)
        #expect(result.liveCount == 2)
        #expect(result.stalledCount == 1)
        #expect(result.liveProjectCount == 1)
        #expect(result.nextCount == 1)
    }

    @Test func todayCompletionUsesCalendarAndIgnoresFutureReopenedAndArchived() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let now = t0
        let midnight = calendar.startOfDay(for: now)
        _ = p.makeCard(in: ctx, title: "today", status: .done, at: midnight)
        _ = p.makeCard(in: ctx, title: "yesterday", status: .done, at: midnight - 1)
        _ = p.makeCard(in: ctx, title: "future", status: .done, at: now + 1)
        let reopened = p.makeCard(in: ctx, title: "reopened", status: .next, at: now)
        reopened.doneAt = midnight
        let archived = makeProject(ctx, key: "ARC"); archived.archivedAt = now
        _ = archived.makeCard(in: ctx, title: "hidden", status: .done, at: now)
        #expect(DashboardOverview(projects: [p, archived], now: now, calendar: calendar).doneTodayCount == 1)
    }

    @Test func resumeCardsExcludeCompletedArchivedActiveAndBlankNotes() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let old = p.makeCard(in: ctx, title: "old", status: .next, at: t0)
        old.nextSessionNote = "continue"
        let recent = p.makeCard(in: ctx, title: "recent", status: .idea, at: t0 + 1)
        recent.nextSessionNote = "continue"
        for status in [CardStatus.done, .archived, .next] {
            let c = p.makeCard(in: ctx, title: "excluded", status: status, at: t0)
            c.nextSessionNote = status == .next ? " \n " : "note"
        }
        let active = p.makeCard(in: ctx, title: "active", status: .next, at: t0)
        active.nextSessionNote = "note"
        CardLifecycle.attach(active, makeSession(ctx, p, id: "live"), at: t0, in: ctx)
        let archived = makeProject(ctx, key: "ARC"); archived.archivedAt = t0
        let hidden = archived.makeCard(in: ctx, title: "hidden", status: .next, at: t0)
        hidden.nextSessionNote = "note"
        #expect(DashboardOverview(projects: [p, archived], now: t0 + 2).resumeCards.map(\.title) == ["recent", "old"])
    }

    @Test func emptyProjectsProduceEmptyOverview() {
        let result = DashboardOverview(projects: [], now: t0)
        #expect(result.groups.isEmpty && result.resumeCards.isEmpty)
        #expect(result.liveCount == 0 && result.stalledCount == 0 && result.nextCount == 0)
        #expect(result.doneTodayCount == 0 && result.liveProjectCount == 0)
    }

    // 다음 할 일 수는 next 카드만 센다.
    @Test func nextCountCountsOnlyNextCards() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        for status in [CardStatus.next, .next, .idea] { _ = p.makeCard(in: ctx, title: "card", status: status, at: t0) }
        #expect(DashboardOverview(projects: [p], now: t0).nextCount == 2)
    }

    // 오늘 끝낸 수는 지금 이 순간 끝낸 카드까지 넣고, 끝낸 시각이 없는 카드와 되돌린 카드는 뺀다.
    @Test func doneTodayIncludesNowAndSkipsCardsWithoutDoneTime() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let midnight = calendar.startOfDay(for: t0)
        _ = p.makeCard(in: ctx, title: "at midnight", status: .done, at: midnight)
        _ = p.makeCard(in: ctx, title: "right now", status: .done, at: t0)
        let untimed = p.makeCard(in: ctx, title: "no done time", status: .done, at: t0)
        untimed.doneAt = nil
        let reopened = p.makeCard(in: ctx, title: "reopened", status: .next, at: t0)
        reopened.doneAt = midnight
        #expect(DashboardOverview(projects: [p], now: t0, calendar: calendar).doneTodayCount == 2)
    }

    // 메모가 아예 없는 카드는 이어 할 카드에 넣지 않는다.
    @Test func resumeCardsSkipCardsWithoutAnyNote() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let noted = p.makeCard(in: ctx, title: "noted", status: .next, at: t0)
        noted.nextSessionNote = "continue"
        _ = p.makeCard(in: ctx, title: "bare", status: .next, at: t0)
        #expect(DashboardOverview(projects: [p], now: t0).resumeCards.map(\.title) == ["noted"])
    }
}
