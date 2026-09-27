import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct SessionStateCacheTests {
    @Test func refreshesOnlyChanged() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let live = makeSession(ctx, p, id: "a", lastSeenAt: t0)
        let stalled = makeSession(ctx, p, id: "b", lastSeenAt: t0 - minutes(16))
        let ended = makeSession(ctx, p, id: "c", lastSeenAt: t0)
        ended.endedAt = t0
        #expect(SessionStateCache.refresh([live, stalled, ended], now: t0) == 2)
        #expect(live.cachedState == .live)
        #expect(stalled.cachedState == .stalled)
        #expect(ended.cachedState == .ended)
        #expect(SessionStateCache.refresh([live, stalled, ended], now: t0) == 0)
    }
}

@Suite struct LastEventCacheTests {
    @Test func recordMovesLastEventForwardOnly() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        #expect(p.lastEventAt == nil)
        let card = p.makeCard(in: ctx, title: "a", at: t0)
        Event.record(.note, in: ctx, card: card, at: t0 + 60, payload: ["text": "x"])
        #expect(p.lastEventAt == t0 + 60)
        Event.record(.note, in: ctx, project: p, at: t0 + 10) // 늦게 온 옛 기록
        #expect(p.lastEventAt == t0 + 60)
        #expect(DashboardQuery.summary(for: p, now: t0 + 120).lastActivityAt == t0 + 60)
    }
}
