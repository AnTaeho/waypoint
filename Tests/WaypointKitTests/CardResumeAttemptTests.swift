import Foundation
import Testing
@testable import WaypointKit

@Suite struct CardResumeAttemptTests {
    @Test func copyAloneDoesNotConnectAndBothProvidersCanConnect() throws {
        for provider in AgentProvider.allCases {
            let h = try HookHarness()
            let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
            let attempt = CardResumeAttempt(card: card, provider: provider, at: t0)
            #expect(attempt.state(for: card) == .waiting)
            #expect(card.status == .next && card.openCardSessions.isEmpty)
            let session = makeSession(h.context, h.project, id: "new")
            session.provider = provider
            CardLifecycle.attach(card, session, at: t0 + 1, in: h.context)
            #expect(attempt.state(for: card) == .connected)
            CardLifecycle.detach(card, session, at: t0 + 2, in: h.context)
            #expect(attempt.state(for: card) == .disconnected)
        }
    }

    @Test func ignoresHistoricalSessionsOtherProvidersAndSubagents() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        let old = makeSession(h.context, h.project, id: "old")
        old.provider = .codex
        CardLifecycle.attach(card, old, at: t0, in: h.context)
        CardLifecycle.detach(card, old, at: t0 + 1, in: h.context)
        let attempt = CardResumeAttempt(card: card, provider: .codex, at: t0 + 2)
        CardLifecycle.attach(card, old, at: t0 + 3, in: h.context)
        let other = makeSession(h.context, h.project, id: "claude")
        CardLifecycle.attach(card, other, at: t0 + 3, in: h.context)
        let sub = makeSession(h.context, h.project, id: "sub", parent: old)
        sub.provider = .codex
        CardLifecycle.attach(card, sub, at: t0 + 3, in: h.context)
        #expect(attempt.state(for: card) == .waiting)
    }

    @Test func requiresLaterLinkAndMatchingProjectAndHandlesEndedSession() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        let attempt = CardResumeAttempt(card: card, provider: .claude, at: t0)
        let session = makeSession(h.context, h.project, id: "new")
        let link = CardLifecycle.attach(card, session, at: t0, in: h.context)
        #expect(attempt.state(for: card) == .waiting)
        link.attachedAt = t0 + 1
        let other = makeProject(h.context, key: "OTH")
        session.project = other
        #expect(attempt.state(for: card) == .waiting)
        session.project = h.project
        #expect(attempt.state(for: card) == .connected)
        session.endedAt = t0 + 2
        #expect(attempt.state(for: card) == .disconnected)
    }

    @Test func cardCompletionArchiveAndDifferentCardStopConfirmation() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        let attempt = CardResumeAttempt(card: card, provider: .claude, at: t0)
        let session = makeSession(h.context, h.project, id: "new")
        CardLifecycle.attach(card, session, at: t0 + 1, in: h.context)
        try CardLifecycle.move(card, to: .done, at: t0 + 2, in: h.context)
        #expect(attempt.state(for: card) == .unavailable("완료한 카드"))
        try CardLifecycle.move(card, to: .next, at: t0 + 3, in: h.context)
        h.project.archivedAt = t0 + 4
        #expect(attempt.state(for: card) == .unavailable("보관한 프로젝트"))
        let other = h.project.makeCard(in: h.context, title: "other", status: .next, at: t0)
        #expect(attempt.state(for: other) == .unavailable("작업 대상 변경됨"))
    }

    // 연결 시각은 지금 열려 있는 새 연결의 것이다. 먼저 붙었다 떨어진 새 세션은 세지 않는다.
    @Test func connectedAtUsesOpenLinkNotEarlierDetachedOne() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        let attempt = CardResumeAttempt(card: card, provider: .claude, at: t0)
        let left = makeSession(h.context, h.project, id: "left")
        CardLifecycle.attach(card, left, at: t0 + 1, in: h.context)
        CardLifecycle.detach(card, left, at: t0 + 2, in: h.context)
        #expect(attempt.connectedAt(for: card) == nil)
        CardLifecycle.attach(card, makeSession(h.context, h.project, id: "stays"), at: t0 + 5, in: h.context)
        #expect(attempt.state(for: card) == .connected)
        #expect(attempt.connectedAt(for: card) == t0 + 5)
    }
}
