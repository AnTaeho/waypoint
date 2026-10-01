import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 요청 문장 보관 30일(`PromptRetention`, SPEC 5장 「요청 문장 보관」).
@Suite struct PromptRetentionTests {
    let day: TimeInterval = 24 * 60 * 60

    @Test func expiryBoundary() {
        #expect(PromptRetention.days == 30)
        #expect(!PromptRetention.isExpired(recordedAt: t0, now: t0 + 30 * day - 1))
        #expect(PromptRetention.isExpired(recordedAt: t0, now: t0 + 30 * day))
    }

    @Test func sessionPromptOnlyAfterEnd() {
        let now = t0 + 40 * day
        #expect(!PromptRetention.isSessionPromptExpired(endedAt: nil, lastPromptAt: t0, now: now))
        #expect(PromptRetention.isSessionPromptExpired(endedAt: t0 + day, lastPromptAt: t0, now: now))
        #expect(!PromptRetention.isSessionPromptExpired(endedAt: t0 + 20 * day, lastPromptAt: t0 + 15 * day, now: now))
        // 요청 시각이 없으면 끝난 시각부터 잰다
        #expect(PromptRetention.isSessionPromptExpired(endedAt: t0 + 10 * day, lastPromptAt: nil, now: now))
        #expect(!PromptRetention.isSessionPromptExpired(endedAt: t0 + 11 * day, lastPromptAt: nil, now: now))
    }

    @Test func runsOnStartThenDaily() {
        #expect(PromptRetention.isDue(lastRun: nil, now: t0))
        #expect(!PromptRetention.isDue(lastRun: t0, now: t0 + day - 1))
        #expect(PromptRetention.isDue(lastRun: t0, now: t0 + day))
    }

    @Test func clearsOnlyOldPromptTextAndKeepsTheEvent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let session = makeSession(ctx, project, id: "s")
        let card = project.makeCard(in: ctx, title: "카드", status: .next, at: t0)
        let old = Event.record(.note, in: ctx, project: project, card: card, session: session, at: t0,
                               payload: ["kind": "user.prompt", "text": "오래된 요청"])
        let recent = Event.record(.note, in: ctx, project: project, session: session, at: t0 + 10 * day,
                                  payload: ["kind": "user.prompt", "text": "최근 요청"])
        let memo = Event.record(.note, in: ctx, project: project, session: session, at: t0,
                                payload: ["kind": "handoff", "text": "옛 메모"])
        let now = t0 + 31 * day

        let result = PromptRetention.apply(in: ctx, now: now)
        #expect(result.events == 1)
        #expect(old.payloadValues == ["kind": "user.prompt"])
        #expect(old.at == t0 && old.session === session && old.card === card && old.project === project)
        #expect(recent.payloadValues["text"] == "최근 요청")
        #expect(memo.payloadValues["text"] == "옛 메모")
        // 두 번째 정리는 바꿀 것이 없다
        #expect(PromptRetention.apply(in: ctx, now: now).events == 0)
    }

    @Test func clearsLastPromptOfEndedSessionsOnly() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let ended = makeSession(ctx, project, id: "ended")
        ended.lastPrompt = "끝난 세션 요청"; ended.lastPromptAt = t0; ended.endedAt = t0 + day
        let open = makeSession(ctx, project, id: "open")
        open.lastPrompt = "열린 세션 요청"; open.lastPromptAt = t0
        let fresh = makeSession(ctx, project, id: "fresh")
        fresh.lastPrompt = "최근 끝난 요청"; fresh.lastPromptAt = t0 + 20 * day; fresh.endedAt = t0 + 20 * day

        let result = PromptRetention.apply(in: ctx, now: t0 + 31 * day)
        #expect(result.sessions == 1)
        #expect(ended.lastPrompt == nil && ended.lastPromptAt == t0)
        #expect(open.lastPrompt == "열린 세션 요청")
        #expect(fresh.lastPrompt == "최근 끝난 요청")
    }

    @Test func clearedPromptShowsAsPlainRequest() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let session = makeSession(ctx, project, id: "s")
        let card = project.makeCard(in: ctx, title: "카드", status: .next, at: t0)
        let cleared = Event.record(.note, in: ctx, project: project, card: card, session: session, at: t0,
                                   payload: ["kind": "user.prompt"])

        let entry = try #require(ActivityEntryFormat.entry(cleared))
        #expect(entry.text == "요청" && entry.detail.isEmpty && entry.kind == "user.prompt")
        #expect(CardHistoryFormat.line(for: cleared)?.text == "요청")
        // 세션 묶음 제목은 지운 요청 대신 세션 이름
        let group = try #require(ProjectActivity.days(events: [cleared], projectID: project.id).first?.groups.first)
        #expect(group.title == SessionFormat.label(for: session))
    }
}
