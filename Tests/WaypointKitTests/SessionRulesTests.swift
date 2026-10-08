import Foundation
import Testing
@testable import WaypointKit

@Suite struct SessionRulesTests {
    @Test func liveWithinTimeout() {
        #expect(SessionRules.state(endedAt: nil, lastSeenAt: t0, now: t0 + minutes(3)) == .live)
    }

    @Test func stalledAfterTimeout() {
        #expect(SessionRules.state(endedAt: nil, lastSeenAt: t0, now: t0 + minutes(15) + 1) == .stalled)
    }

    @Test func exactlyTimeoutIsLive() {
        #expect(SessionRules.state(endedAt: nil, lastSeenAt: t0, now: t0 + minutes(15)) == .live)
    }

    @Test func endedWins() {
        #expect(SessionRules.state(endedAt: t0, lastSeenAt: t0, now: t0 + minutes(1)) == .ended)
        #expect(SessionRules.state(endedAt: t0, lastSeenAt: t0, now: t0 + minutes(60)) == .ended)
    }

    @Test func customTimeout() {
        #expect(SessionRules.state(endedAt: nil, lastSeenAt: t0, now: t0 + minutes(6), stallTimeout: minutes(5)) == .stalled)
    }
}

@Suite struct CardWorkStateTests {
    @Test func liveWhenAnyLive() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let stale = makeSession(ctx, p, id: "s1", lastSeenAt: t0)
        let fresh = makeSession(ctx, p, id: "s2", lastSeenAt: t0 + minutes(20))
        CardLifecycle.attach(card, stale, at: t0, in: ctx)
        CardLifecycle.attach(card, fresh, at: t0, in: ctx)
        #expect(CardRules.workState(of: card, now: t0 + minutes(25)) == .live)
    }

    @Test func stalledWhenAllStalled() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        CardLifecycle.attach(card, makeSession(ctx, p, id: "s1"), at: t0, in: ctx)
        CardLifecycle.attach(card, makeSession(ctx, p, id: "s2"), at: t0, in: ctx)
        #expect(CardRules.workState(of: card, now: t0 + minutes(30)) == .stalled)
    }

    @Test func noneWithoutOpenLinks() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", at: t0)
        #expect(CardRules.workState(of: card, now: t0) == .none)

        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        CardLifecycle.detach(card, s, at: t0 + 1, in: ctx)
        #expect(CardRules.workState(of: card, now: t0 + 2) == .none)
    }
}

@Suite struct ProjectCardNumberTests {
    @Test func numbersIncreaseAndDisplayID() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        p.nextCardNumber = 14
        let a = p.makeCard(in: ctx, title: "a", at: t0)
        let b = p.makeCard(in: ctx, title: "b", at: t0)
        #expect(a.number == 14)
        #expect(b.number == 15)
        #expect(p.nextCardNumber == 16)
        #expect(a.displayID == "LDG-14")
        #expect(p.cards?.count == 2)
    }

    @Test func displayIDWithoutProject() {
        #expect(Card(number: 3, title: "x").displayID == "?-3")
    }
}

@Suite struct UnassignedWorkTests {
    // 완료한 카드에서 떨어진 바로 그 시각의 요청은 새 요청으로 치지 않는다. 그 뒤의 요청부터 다시 줄이 된다.
    @Test func promptAtDetachTimeDoesNotReviveCardlessRow() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "s")
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        try CardLifecycle.move(card, to: .done, at: t0 + 60, in: ctx)
        s.lastPromptAt = t0 + 60
        #expect(!SessionRules.hasUnassignedWork(s, now: t0 + 60))
        s.lastPromptAt = t0 + 61
        #expect(SessionRules.hasUnassignedWork(s, now: t0 + 61))
    }
}
