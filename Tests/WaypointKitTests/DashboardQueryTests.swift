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

    /// 부모 세션 줄이 없으면(부모가 끝남) 서브에이전트 줄이 맨 위 단계에 선다.
    /// 끝나지 않은 부모는 카드가 없어도 줄이 생기므로, 줄 없는 부모를 만들려면 끝내야 한다.
    @Test func orphanSubagentIsTopLevel() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let main = makeSession(ctx, p, id: "main")
        let sub = makeSession(ctx, p, id: "sub", parent: main)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "a", at: t0), sub, at: t0, in: ctx)
        main.endedAt = t0
        let rows = DashboardQuery.rows(for: p, now: t0)
        #expect(rows.map(\.session.id) == ["sub"])
        #expect(rows.first?.depth == 0)
    }

    @Test func cardlessMainSessionGetsRow() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let now = t0 + minutes(30)
        let live = makeSession(ctx, p, id: "live", startedAt: t0, lastSeenAt: now)
        _ = makeSession(ctx, p, id: "stalled", startedAt: t0 + minutes(1), lastSeenAt: t0 + minutes(1))
        let ended = makeSession(ctx, p, id: "ended", startedAt: t0 + minutes(2), lastSeenAt: now)
        ended.endedAt = now
        // 카드 없는 서브에이전트는 줄이 되지 않는다(부모 줄로 충분)
        _ = makeSession(ctx, p, id: "sub", startedAt: t0 + minutes(3), lastSeenAt: now, parent: live)

        let rows = DashboardQuery.rows(for: p, now: now)
        #expect(rows.map(\.session.id) == ["live", "stalled"])
        #expect(rows.allSatisfy { $0.card == nil && $0.depth == 0 })
        #expect(rows.map(\.workState) == [.live, .stalled])
        #expect(Set(rows.map(\.id)).count == 2)
    }

    /// 카드 줄은 그 카드에 연결된 시각을 싣고(경과 기준), 카드 없는 줄은 nil.
    @Test func rowCarriesLinkAttachedAt() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let now = t0 + minutes(60)
        let withCard = makeSession(ctx, p, id: "card", startedAt: t0, lastSeenAt: now)
        _ = makeSession(ctx, p, id: "free", startedAt: t0 + minutes(1), lastSeenAt: now)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "a", at: t0), withCard, at: t0 + minutes(40), in: ctx)

        let rows = DashboardQuery.rows(for: p, now: now)
        #expect(rows.map(\.session.id) == ["card", "free"])
        #expect(rows.map(\.attachedAt) == [t0 + minutes(40), nil])
    }

    @Test func cardlessRowTurnsIntoCardRowWithoutDuplicate() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "main")
        #expect(DashboardQuery.rows(for: p, now: t0).map(\.card) == [nil])

        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0 + 1, in: ctx)
        let rows = DashboardQuery.rows(for: p, now: t0 + 1)
        #expect(rows.count == 1)
        #expect(rows.first?.card === card)

        // 연결이 끝나면 다시 카드 없는 줄
        CardLifecycle.detach(card, s, at: t0 + 2, in: ctx)
        #expect(DashboardQuery.rows(for: p, now: t0 + 2).map(\.card) == [nil])
    }

    @Test func subagentCardRowNestsUnderCardlessParent() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let main = makeSession(ctx, p, id: "main")
        let sub = makeSession(ctx, p, id: "sub", startedAt: t0 + 1, parent: main)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "a", at: t0), sub, at: t0 + 1, in: ctx)
        let rows = DashboardQuery.rows(for: p, now: t0 + 1)
        #expect(rows.map(\.session.id) == ["main", "sub"])
        #expect(rows.map(\.depth) == [0, 1])
        #expect(rows.first?.card == nil)
    }

    @Test func cardlessRecentFileComesFromSessionAndItsSubagents() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let main = makeSession(ctx, p, id: "main")
        let sub = makeSession(ctx, p, id: "sub", parent: main)
        let other = makeSession(ctx, p, id: "other")
        func changed(_ s: Session, _ path: String, at: Date, card: Card? = nil) {
            Event.record(.fileChanged, in: ctx, project: p, card: card, session: s, at: at, payload: ["path": .string(path)])
        }
        #expect(SessionFormat.recentFileName(session: main) == nil)
        changed(main, "Sources/A.swift", at: t0 + 1)
        changed(sub, "Tests/B.swift", at: t0 + 2)
        changed(other, "C.swift", at: t0 + 3)
        changed(main, "D.swift", at: t0 + 4, card: p.makeCard(in: ctx, title: "x", at: t0)) // 카드 기록은 제외
        #expect(SessionFormat.recentFileName(session: main) == "B.swift")
        #expect(SessionFormat.recentFileName(session: other) == "C.swift")
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

    /// 사이드바·프로젝트 표 개수도 대시보드 줄과 같은 기준: 카드 없이 도는 메인 세션을 센다(서브에이전트·끝난 세션은 빼고).
    @Test func summaryCountsCardlessMainSessions() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let now = t0 + minutes(30)
        let a = makeSession(ctx, p, id: "a", lastSeenAt: now)
        _ = makeSession(ctx, p, id: "b", lastSeenAt: now)
        _ = makeSession(ctx, p, id: "c", lastSeenAt: t0)
        makeSession(ctx, p, id: "d", lastSeenAt: now).endedAt = now
        _ = makeSession(ctx, p, id: "sub", lastSeenAt: now, parent: a)
        let s = DashboardQuery.summary(for: p, now: now)
        #expect(s.liveCount == 2)
        #expect(s.stalledCount == 1)

        // 카드가 붙으면 카드로 한 번만 센다
        CardLifecycle.attach(p.makeCard(in: ctx, title: "x", status: .next, at: t0), a, at: now, in: ctx)
        #expect(DashboardQuery.summary(for: p, now: now).liveCount == 2)
    }

    // 같은 상태의 프로젝트는 이름순, 이름까지 같으면 키순.
    @Test func groupsOrderByNameThenKey() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let projects = [("AAA", "하 프로젝트"), ("ZZZ", "가 프로젝트"), ("MMM", "나 프로젝트"), ("BBB", "나 프로젝트")].map {
            makeProject(ctx, key: $0.0, name: $0.1)
        }
        for project in projects { _ = makeSession(ctx, project, id: "s-\(project.key)") }
        #expect(DashboardQuery.groups(for: projects, now: t0).map(\.project.key) == ["ZZZ", "BBB", "MMM", "AAA"])
    }

    // 같은 세션의 줄은 카드에 붙은 순서다. 시작·연결 시각이 모두 같으면 카드 번호순(세션 ID순보다 먼저).
    @Test func rowsOrderByAttachTimeThenCardNumber() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "s")
        let first = p.makeCard(in: ctx, title: "first", status: .next, at: t0)
        let second = p.makeCard(in: ctx, title: "second", status: .next, at: t0)
        CardLifecycle.attach(second, s, at: t0 + 1, in: ctx)
        CardLifecycle.attach(first, s, at: t0 + 2, in: ctx)
        #expect(DashboardQuery.rows(for: p, now: t0 + 2).map(\.card?.title) == ["second", "first"])

        let q = makeProject(ctx, key: "QQQ", name: "다른")
        let low = q.makeCard(in: ctx, title: "low", status: .next, at: t0)
        let high = q.makeCard(in: ctx, title: "high", status: .next, at: t0)
        CardLifecycle.attach(low, makeSession(ctx, q, id: "b"), at: t0, in: ctx)
        CardLifecycle.attach(high, makeSession(ctx, q, id: "a"), at: t0, in: ctx)
        #expect(DashboardQuery.rows(for: q, now: t0).map(\.session.id) == ["b", "a"])
    }

    // 줄을 만들 세션은 이 프로젝트의 끝나지 않은 것만 읽는다.
    @Test func openSessionsSkipEndedAndOtherProjects() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let other = makeProject(ctx, key: "OTH", name: "다른")
        _ = makeSession(ctx, p, id: "open")
        makeSession(ctx, p, id: "ended").endedAt = t0
        _ = makeSession(ctx, other, id: "elsewhere")
        try ctx.save()
        #expect(DashboardQuery.openSessions(of: p).map(\.id) == ["open"])
    }

    // 저장소에 넣지 않은 프로젝트도 끝나지 않은 세션만 줄이 된다.
    @Test func projectOutsideAStoreListsOnlyOpenSessions() {
        let p = Project(key: "TMP", name: "임시", createdAt: t0)
        let open = Session(id: "open", startedAt: t0, lastSeenAt: t0)
        let ended = Session(id: "ended", startedAt: t0, lastSeenAt: t0)
        ended.endedAt = t0
        p.sessions = [open, ended]
        #expect(DashboardQuery.openSessions(of: p).map(\.id) == ["open"])
    }

    // 가장 최근 세션들이 저장 전에 다른 프로젝트로 옮겨 가도 남은 세션의 활동 시각을 찾는다.
    @Test func latestSessionActivitySkipsSessionsMovingOut() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let other = makeProject(ctx, key: "OTH", name: "다른")
        let newest = makeSession(ctx, p, id: "newest", lastSeenAt: t0 + 300)
        let newer = makeSession(ctx, p, id: "newer", lastSeenAt: t0 + 200)
        _ = makeSession(ctx, p, id: "stays", lastSeenAt: t0 + 100)
        try ctx.save()
        newest.project = other
        newer.project = other
        #expect(DashboardQuery.latestSessionActivity(of: p) == t0 + 100)
    }
}
