import Foundation
import Testing
@testable import WaypointKit

@Suite struct IdeaInboxTests {
    @Test func recentIdeasNewestFirst() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let old = p.makeCard(in: ctx, title: "old", status: .idea, at: t0)
        let a = p.makeCard(in: ctx, title: "a", status: .idea, at: t0 + minutes(60 * 24 * 2))
        let b = p.makeCard(in: ctx, title: "b", status: .idea, at: t0 + minutes(60 * 24 * 5))
        _ = p.makeCard(in: ctx, title: "next", status: .next, at: t0 + minutes(60 * 24 * 5))
        let now = t0 + minutes(60 * 24 * 8)

        let recent = IdeaInbox.recent(p.cards ?? [], now: now)
        #expect(recent.map(\.title) == ["b", "a"])
        // 경계: 정확히 7일 전은 들어간다
        #expect(IdeaInbox.recent([old], now: t0 + IdeaInbox.defaultWindow).map(\.title) == ["old"])
        #expect(IdeaInbox.recent([old, a, b], now: now, window: minutes(60 * 24 * 4)).map(\.title) == ["b"])
    }

    @Test func skipsArchivedProjectAndMovedCards() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let q = makeProject(ctx, key: "OLD", name: "옛것")
        q.archivedAt = t0
        let kept = p.makeCard(in: ctx, title: "kept", status: .idea, at: t0)
        let hidden = q.makeCard(in: ctx, title: "hidden", status: .idea, at: t0)
        let moved = p.makeCard(in: ctx, title: "moved", status: .idea, at: t0)
        try CardLifecycle.move(moved, to: .next, at: t0 + minutes(1), in: ctx)

        #expect(IdeaInbox.recent([kept, hidden, moved], now: t0 + minutes(2)).map(\.title) == ["kept"])
    }
}
