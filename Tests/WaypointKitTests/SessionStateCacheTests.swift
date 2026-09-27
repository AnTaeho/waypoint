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
