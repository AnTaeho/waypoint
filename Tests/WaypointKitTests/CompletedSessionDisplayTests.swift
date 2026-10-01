import Foundation
import Testing
@testable import WaypointKit

@Suite struct CompletedSessionDisplayTests {
    @Test func completingLastCardHidesCardlessTileWithoutEndingSession() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "s")
        s.lastPromptAt = t0
        let card = p.makeCard(in: ctx, title: "work", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        try CardLifecycle.move(card, to: .done, at: t0 + 1, in: ctx)
        #expect(s.endedAt == nil)
        #expect(BoardQuery.sessionTiles(for: p, now: t0 + 2).isEmpty)
        #expect(DashboardQuery.rows(for: p, now: t0 + 2).isEmpty)
        #expect(DashboardQuery.summary(for: p, now: t0 + 2).liveCount == 0)
        #expect(BoardQuery.columns(for: p, now: t0 + 2)[.done]?.count == 1)
        s.lastSeenAt = t0 + 3 // Stop나 도구 출력만으로 완료한 작업을 다시 보여주지 않는다.
        #expect(DashboardQuery.rows(for: p, now: t0 + 3).isEmpty)
        s.lastPromptAt = t0 + 4
        #expect(DashboardQuery.rows(for: p, now: t0 + 4).count == 1)
        #expect(DashboardQuery.summary(for: p, now: t0 + 4).liveCount == 1)
    }

    @Test func plainDetachOrPauseKeepsUnassignedWorkVisible() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "s")
        let card = p.makeCard(in: ctx, title: "work", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        CardLifecycle.detach(card, s, at: t0 + 1, in: ctx)
        #expect(BoardQuery.sessionTiles(for: p, now: t0 + 2).count == 1)
    }

    @Test func activeSubagentKeepsParentVisibleAfterMainCardCompletes() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "s")
        let sub = makeSession(ctx, p, id: "sub", parent: s)
        let card = p.makeCard(in: ctx, title: "work", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        try CardLifecycle.move(card, to: .done, at: t0 + 1, in: ctx)
        #expect(BoardQuery.sessionTiles(for: p, now: t0 + 2).count == 1)
        sub.endedAt = t0 + 3
        #expect(BoardQuery.sessionTiles(for: p, now: t0 + 3).isEmpty)
    }
}
