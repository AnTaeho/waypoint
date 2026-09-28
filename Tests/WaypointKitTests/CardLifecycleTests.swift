import Foundation
import Testing
@testable import WaypointKit

@Suite struct CardLifecycleTests {
    @Test func attachMakesActiveAndRemembers() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0 + 1, in: ctx)
        #expect(card.status == .active)
        #expect(card.statusBeforeActive == "next")
        #expect(card.openCardSessions.count == 1)
        #expect(events(card, .cardAttached).count == 1)
        #expect(events(card, .cardStatus).count == 1)
    }

    @Test func attachToActiveKeepsRememberedStatus() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .idea, at: t0)
        CardLifecycle.attach(card, makeSession(ctx, p, id: "s1"), at: t0, in: ctx)
        CardLifecycle.attach(card, makeSession(ctx, p, id: "s2"), at: t0 + 1, in: ctx)
        #expect(card.status == .active)
        #expect(card.statusBeforeActive == "idea")
        #expect(events(card, .cardStatus).count == 1)
        #expect(events(card, .cardAttached).count == 2)
    }

    @Test func attachSamePairTwiceIsNoop() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        let first = CardLifecycle.attach(card, s, at: t0, in: ctx)
        let second = CardLifecycle.attach(card, s, at: t0 + 1, in: ctx)
        #expect(first === second)
        #expect(card.openCardSessions.count == 1)
    }

    @Test func detachLastRestoresPreviousStatus() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        CardLifecycle.detach(card, s, at: t0 + 10, in: ctx)
        #expect(card.status == .next)
        #expect(card.statusBeforeActive == nil)
        #expect(card.openCardSessions.isEmpty)
        #expect(card.cardSessions?.first?.detachedAt == t0 + 10)
        #expect(events(card, .cardDetached).count == 1)
        #expect(events(card, .cardStatus).count == 2)
    }

    @Test func detachWithOtherOpenLinkStaysActive() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s1 = makeSession(ctx, p, id: "s1")
        let s2 = makeSession(ctx, p, id: "s2")
        CardLifecycle.attach(card, s1, at: t0, in: ctx)
        CardLifecycle.attach(card, s2, at: t0, in: ctx)
        CardLifecycle.detach(card, s1, at: t0 + 1, in: ctx)
        #expect(card.status == .active)
        #expect(card.statusBeforeActive == "next")
        #expect(card.openCardSessions.count == 1)
        CardLifecycle.detach(card, s2, at: t0 + 2, in: ctx)
        #expect(card.status == .next)
    }

    @Test func userMovedToDoneThenDetachStaysDone() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        try CardLifecycle.move(card, to: .done, at: t0 + 5, in: ctx)
        #expect(card.openCardSessions.isEmpty) // active를 떠나면 연결이 닫힌다
        #expect(card.statusBeforeActive == nil)
        CardLifecycle.detach(card, s, at: t0 + 10, in: ctx) // 이미 닫혀 아무 일 없음
        #expect(card.status == .done)
        #expect(card.doneAt == t0 + 5)
        #expect(events(card, .cardDetached).count == 1)
    }

    @Test func ideaDetachReturnsToIdeaNotDone() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .idea, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        CardLifecycle.detach(card, s, at: t0 + 1, in: ctx)
        #expect(card.status == .idea)
        #expect(card.doneAt == nil)
    }

    @Test func detachWithoutRememberedStatusFallsBackToNext() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        card.statusBeforeActive = nil
        CardLifecycle.detach(card, s, at: t0 + 1, in: ctx)
        #expect(card.status == .next)
    }

    @Test func detachAllEndsSession() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let a = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let b = p.makeCard(in: ctx, title: "b", status: .idea, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(a, s, at: t0, in: ctx)
        CardLifecycle.attach(b, s, at: t0, in: ctx)
        CardLifecycle.detachAll(s, at: t0 + 60, in: ctx)
        #expect(s.endedAt == t0 + 60)
        #expect(s.cachedState == .ended)
        #expect(s.openCardSessions.isEmpty)
        #expect(a.status == .next)
        #expect(b.status == .idea)
        #expect(SessionRules.state(of: s, now: t0 + 61) == .ended)
    }

    @Test func moveToActiveIsRejected() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        #expect(throws: CardLifecycleError.cannotMoveToActive) {
            try CardLifecycle.move(card, to: .active, at: t0, in: ctx)
        }
        #expect(card.status == .next)
    }

    @Test func moveSetsAndClearsDoneAt() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        try CardLifecycle.move(card, to: .done, at: t0 + 1, in: ctx)
        #expect(card.status == .done)
        #expect(card.doneAt == t0 + 1)
        #expect(card.updatedAt == t0 + 1)
        try CardLifecycle.move(card, to: .next, at: t0 + 2, in: ctx)
        #expect(card.doneAt == nil)
        #expect(events(card, .cardStatus).count == 2)
    }

    @Test func moveToSameStatusIsNoop() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        try CardLifecycle.move(card, to: .next, at: t0 + 1, in: ctx)
        #expect(events(card, .cardStatus).isEmpty)
        #expect(card.updatedAt == t0)
    }
}
