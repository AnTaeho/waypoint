import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct TrackingReconnectTests {
    @Test func expiredSessionReconnectsWithoutRestoringOldWorkOrPID() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "codex:real")
        s.provider = .codex
        let card = p.makeCard(in: ctx, title: "work", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        try ctx.save()
        let processor = HookProcessor(context: ctx)
        #expect(processor.sweep(now: t0 + 31 * 60, probe: { _ in nil }) == 1)
        #expect(card.status == .next && card.doneAt == nil && s.openCardSessions.isEmpty)
        s.processPid = 4242
        let tools = MCPTools(context: ctx, now: { t0 + 32 * 60 })
        _ = try tools.call("session_bind", ["project": "LDG", "sessionId": "codex:real",
                                           "provider": "codex", "cwd": "/workspace"])
        #expect(s.endedAt == nil && s.processPid == nil && s.cachedState == .live)
        #expect(s.lastSeenAt == t0 + 32 * 60)
        #expect(s.openCardSessions.isEmpty && card.status == .next)
        #expect((s.events ?? []).contains { $0.type == .sessionEnd })
        _ = try tools.call("card_start", ["id": .string(card.displayID), "sessionId": "codex:real"])
        #expect(card.status == .active)
    }

    @Test func explicitEndCannotBeReconnectedByBinding() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "main")
        HookProcessor(context: ctx).finish(s, at: t0 + 60, reason: "logout")
        let tools = MCPTools(context: ctx, now: { t0 + 120 })
        #expect(throws: MCPToolError.self) {
            try tools.call("session_bind", ["project": "LDG", "sessionId": "main",
                                           "provider": "claude", "cwd": "/workspace"])
        }
        #expect(s.endedAt == t0 + 60)
    }
}
