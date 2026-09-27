import Foundation
import Testing
@testable import WaypointKit

@Suite struct DashboardQueryTests {
    @Test func subagentRowSitsUnderParent() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let main = makeSession(ctx, p, id: "main", startedAt: t0)
        let other = makeSession(ctx, p, id: "other", startedAt: t0 + minutes(1))
        let sub = makeSession(ctx, p, id: "sub", startedAt: t0 + minutes(2), parent: main)
        let a = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let b = p.makeCard(in: ctx, title: "b", status: .next, at: t0)
        let c = p.makeCard(in: ctx, title: "c", status: .next, parent: a, at: t0)
        CardLifecycle.attach(a, main, at: t0, in: ctx)
        CardLifecycle.attach(b, other, at: t0, in: ctx)
        CardLifecycle.attach(c, sub, at: t0 + minutes(2), in: ctx)

        let rows = DashboardQuery.rows(for: p, now: t0 + minutes(3))
        #expect(rows.map(\.session.id) == ["main", "sub", "other"])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows.allSatisfy { $0.workState == .live })
    }

    @Test func orphanSubagentIsTopLevel() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let main = makeSession(ctx, p, id: "main")
        let sub = makeSession(ctx, p, id: "sub", parent: main)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "a", at: t0), sub, at: t0, in: ctx)
        let rows = DashboardQuery.rows(for: p, now: t0)
        #expect(rows.count == 1)
        #expect(rows.first?.depth == 0)
    }

    @Test func includesStalledExcludesEnded() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let live = makeSession(ctx, p, id: "live", lastSeenAt: t0 + minutes(25))
        let stalled = makeSession(ctx, p, id: "stalled", lastSeenAt: t0)
        let ended = makeSession(ctx, p, id: "ended", lastSeenAt: t0 + minutes(25))
        CardLifecycle.attach(p.makeCard(in: ctx, title: "a", at: t0), live, at: t0, in: ctx)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "b", at: t0), stalled, at: t0, in: ctx)
        let c = p.makeCard(in: ctx, title: "c", at: t0)
        CardLifecycle.attach(c, ended, at: t0, in: ctx)
        ended.endedAt = t0 + minutes(26) // 연결이 열린 채 끝난 비정상 경우도 제외

        let rows = DashboardQuery.rows(for: p, now: t0 + minutes(26))
        #expect(Set(rows.map(\.session.id)) == ["live", "stalled"])
        #expect(rows.first { $0.session.id == "stalled" }?.workState == .stalled)
    }

    @Test func groupsPerProjectLiveFirst() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let alpha = makeProject(ctx, key: "AAA", name: "가 프로젝트")
        let beta = makeProject(ctx, key: "BBB", name: "나 프로젝트")
        let gamma = makeProject(ctx, key: "CCC", name: "다 프로젝트")
        _ = makeProject(ctx, key: "DDD", name: "라 프로젝트") // 줄 없음 → 빠짐
        let now = t0 + minutes(30)
        CardLifecycle.attach(alpha.makeCard(in: ctx, title: "a", at: t0), makeSession(ctx, alpha, id: "a", lastSeenAt: t0), at: t0, in: ctx)
        CardLifecycle.attach(beta.makeCard(in: ctx, title: "b", at: t0), makeSession(ctx, beta, id: "b1", lastSeenAt: now), at: t0, in: ctx)
        CardLifecycle.attach(beta.makeCard(in: ctx, title: "b2", at: t0), makeSession(ctx, beta, id: "b2", lastSeenAt: now), at: t0, in: ctx)
        CardLifecycle.attach(gamma.makeCard(in: ctx, title: "c", at: t0), makeSession(ctx, gamma, id: "c", lastSeenAt: now), at: t0, in: ctx)
        try ctx.save()

        let groups = try DashboardQuery.groups(in: ctx, now: now)
        #expect(groups.map(\.project.key) == ["BBB", "CCC", "AAA"])
        #expect(groups.map(\.rows.count) == [2, 1, 1])
    }

    @Test func summaryCounts() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let now = t0 + minutes(30)
        _ = p.makeCard(in: ctx, title: "i1", status: .idea, at: t0)
        _ = p.makeCard(in: ctx, title: "i2", status: .idea, at: t0)
        _ = p.makeCard(in: ctx, title: "n", status: .next, at: t0)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "live", status: .next, at: t0),
                             makeSession(ctx, p, id: "l", lastSeenAt: now), at: t0, in: ctx)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "stalled", status: .next, at: t0),
                             makeSession(ctx, p, id: "s", lastSeenAt: t0), at: t0, in: ctx)
        let s = DashboardQuery.summary(for: p, now: now)
        #expect(s.liveCount == 1)
        #expect(s.stalledCount == 1)
        #expect(s.nextCount == 1)
        #expect(s.ideaCount == 2)
        #expect(s.lastActivityAt == now)
    }
}
