import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 불변식 「열린 연결이 있으면 카드는 active」: active를 떠나는 모든 경로가 연결을 닫고, 점검이 어긋난 데이터를 닫는다.
@Suite struct LeaveActiveTests {

    @Test(arguments: [CardStatus.idea, .next, .done, .archived])
    func moveOutOfActiveClosesLinksWithoutRestore(_ target: CardStatus) throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1")
        CardLifecycle.attach(card, s, at: t0, in: ctx)

        try CardLifecycle.move(card, to: target, at: t0 + 5, in: ctx)
        #expect(card.status == target) // statusBeforeActive(next)로 돌아가지 않는다
        #expect(card.statusBeforeActive == nil)
        #expect(card.openCardSessions.isEmpty)
        #expect(card.cardSessions?.first?.detachedAt == t0 + 5)
        #expect(s.openCardSessions.isEmpty)
        #expect(s.endedAt == nil) // 세션은 그대로 돈다

        let detached = events(card, .cardDetached)
        #expect(detached.count == 1)
        #expect(detached.first?.session === s)
        #expect(detached.first?.payloadValues["sessionId"] == "s1")
        #expect(detached.first?.payloadValues["reason"] == .string(CardLifecycle.reasonMoved))
        // 상태 이벤트는 active → target 하나만(복귀 이벤트 없음)
        let status = events(card, .cardStatus).filter { $0.at == t0 + 5 }
        #expect(status.map { $0.payloadValues["to"] } == [.string(target.rawValue)])
    }

    @Test func moveClosesMainAndSubagentLinks() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .idea, at: t0)
        let main = makeSession(ctx, p, id: "main")
        let sub = makeSession(ctx, p, id: "sub", parent: main)
        let other = makeSession(ctx, p, id: "other")
        CardLifecycle.attach(card, main, at: t0, in: ctx)
        CardLifecycle.attach(card, sub, at: t0 + 1, in: ctx)
        CardLifecycle.attach(card, other, at: t0 + 2, in: ctx)
        #expect(card.openCardSessions.count == 3)

        try CardLifecycle.move(card, to: .next, at: t0 + 10, in: ctx)
        #expect(card.openCardSessions.isEmpty)
        #expect(sub.openCardSessions.isEmpty)
        #expect(Set(events(card, .cardDetached).compactMap { $0.session?.id }) == ["main", "sub", "other"])
        #expect(card.status == .next)
    }

    @Test func moveBetweenNonActiveStatusesLeavesNoEvents() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .idea, at: t0)
        try CardLifecycle.move(card, to: .next, at: t0 + 1, in: ctx)
        #expect(events(card, .cardDetached).isEmpty)
    }

    @Test func cardUpdateStatusClosesLinks() throws {
        let h = try MCPHarness()
        let a = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        _ = try h.ok("card_start", ["id": "PRB-1", "sessionId": .string(MCPHarness.sessionID)])
        #expect(a.status == .active)

        _ = try h.ok("card_update", ["id": "PRB-1", "status": "idea"])
        #expect(a.status == .idea)
        #expect(a.openCardSessions.isEmpty)
        #expect(h.session.openCardSessions.isEmpty)
        #expect(events(a, .cardDetached).first?.payloadValues["reason"] == .string(CardLifecycle.reasonMoved))

        // 다시 card_start 하면 idea에서 active로(기억된 상태는 idea)
        _ = try h.ok("card_start", ["id": "PRB-1", "sessionId": .string(MCPHarness.sessionID)])
        #expect(a.status == .active)
        #expect(a.statusBeforeActive == "idea")
    }

    @Test func detachedSessionBecomesNoCardTileAndCountsAgree() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        // 멈춘 세션(마지막 활동 20분 전)
        let s = makeSession(ctx, p, id: "s1", startedAt: t0, lastSeenAt: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        let now = t0 + minutes(20)

        try CardLifecycle.move(card, to: .idea, at: now, in: ctx)
        let columns = BoardQuery.columns(for: p, now: now)
        let tiles = BoardQuery.sessionTiles(for: p, now: now)
        let summary = DashboardQuery.summary(for: p, now: now)
        #expect(columns[.active]?.isEmpty == true)
        #expect(tiles.map(\.session.id) == ["s1"])
        #expect(tiles.first?.workState == .stalled)
        #expect(summary.stalledCount == 1 && summary.liveCount == 0)
        #expect((columns[.active]?.count ?? 0) + tiles.count == summary.liveCount + summary.stalledCount)
        let rows = DashboardQuery.rows(for: p, now: now)
        #expect(rows.count == 1 && rows.first?.card == nil)
    }

    // MARK: - 점검(어긋난 기존 데이터)

    @Test func strayJudgement() {
        for status in CardStatus.allCases {
            #expect(CardLifecycle.isStrayLink(cardStatus: status, detachedAt: nil) == (status != .active))
            #expect(CardLifecycle.isStrayLink(cardStatus: status, detachedAt: t0) == false)
        }
    }

    /// 불변식 이전 데이터: 카드 상태만 idea로 바뀌고 연결이 열린 채(NHG-2).
    @Test func closeStrayLinksRepairsOldData() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let stray = p.makeCard(in: ctx, title: "stray", status: .next, at: t0)
        let working = p.makeCard(in: ctx, title: "working", status: .next, at: t0)
        let main = makeSession(ctx, p, id: "main", lastSeenAt: t0)
        let sub = makeSession(ctx, p, id: "sub", lastSeenAt: t0, parent: main)
        let other = makeSession(ctx, p, id: "other", lastSeenAt: t0)
        CardLifecycle.attach(stray, main, at: t0, in: ctx)
        CardLifecycle.attach(stray, sub, at: t0, in: ctx)
        CardLifecycle.attach(working, other, at: t0, in: ctx)
        stray.status = .idea // 옛 move처럼 연결을 두고 상태만 바꾼다
        stray.statusBeforeActive = nil
        stray.updatedAt = t0 + 1
        let now = t0 + minutes(20)
        // 고치기 전: 요약은 멈춤 2(stray 카드 + other 카드), 보드 작업중 칸은 working 하나
        #expect(DashboardQuery.summary(for: p, now: now).stalledCount == 2)
        #expect(BoardQuery.columns(for: p, now: now)[.active]?.count == 1)

        #expect(CardLifecycle.closeStrayLinks(at: now, in: ctx) == 2)
        #expect(stray.openCardSessions.isEmpty)
        #expect(stray.status == .idea) // 상태는 그대로
        #expect(stray.updatedAt == t0 + 1) // 카드 수정 시각도 그대로(CloudKit 병합 기준)
        #expect(working.openCardSessions.count == 1)
        let detached = events(stray, .cardDetached).filter { $0.at == now }
        #expect(Set(detached.compactMap { $0.session?.id }) == ["main", "sub"])
        #expect(detached.allSatisfy { $0.payloadValues["reason"] == .string(CardLifecycle.reasonStatusNotActive) })

        // 고친 뒤: 요약 멈춤 2 = 작업중 칸 카드 1 + 카드 없는 세션 타일 1
        let summary = DashboardQuery.summary(for: p, now: now)
        let active = BoardQuery.columns(for: p, now: now)[.active]?.count ?? 0
        let tiles = BoardQuery.sessionTiles(for: p, now: now)
        #expect(tiles.map(\.session.id) == ["main"])
        #expect(summary.stalledCount == 2)
        #expect(active + tiles.count == summary.liveCount + summary.stalledCount)

        // 두 번째 점검은 할 일이 없다
        #expect(CardLifecycle.closeStrayLinks(at: now + 60, in: ctx) == 0)
    }
}
