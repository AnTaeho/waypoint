import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct BoardQueryTests {
    let now = t0 + 7 * 24 * 3600

    private func ledger(_ ctx: ModelContext) throws -> Project {
        try SampleData.seedIfEmpty(ctx, now: now)
        return try #require(try ctx.fetch(FetchDescriptor<Project>()).first { $0.key == "LDG" })
    }

    @Test func sampleBoardMatchesDesign() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let columns = BoardQuery.columns(for: try ledger(ctx), now: now)
        func numbers(_ c: BoardColumn) -> [Int] { (columns[c] ?? []).map(\.card.number) }
        #expect(numbers(.idea) == [21, 19, 12, 8, 6, 3])
        #expect(numbers(.next) == [15, 17, 18, 20])
        #expect(numbers(.active) == [14, 16])
        #expect((columns[.active] ?? []).map(\.depth) == [0, 1])
        #expect(numbers(.done) == [13, 11, 10])
    }

    @Test func archivedAndOldDoneAreHidden() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let old = p.makeCard(in: ctx, title: "old", status: .done, at: t0)
        let recent = p.makeCard(in: ctx, title: "recent", status: .done, at: now - 60)
        p.makeCard(in: ctx, title: "archived", status: .archived, at: now)
        let columns = BoardQuery.columns(for: p, now: now)
        let all = BoardColumn.allCases.flatMap { columns[$0] ?? [] }.map(\.card.id)
        #expect(all == [recent.id])
        #expect(!all.contains(old.id))
    }

    @Test func childWithoutParentInColumnIsNotIndented() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let parent = p.makeCard(in: ctx, title: "parent", status: .next, at: t0)
        let child = p.makeCard(in: ctx, title: "child", status: .next, parent: parent, at: t0)
        let s = makeSession(ctx, p, id: "s1", lastSeenAt: now)
        CardLifecycle.attach(child, s, at: now, in: ctx)
        let active = BoardQuery.columns(for: p, now: now)[.active] ?? []
        #expect(active.map(\.card.id) == [child.id])
        #expect(active.map(\.depth) == [0])
    }

    @Test func activeColumnRejectsDrop() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        #expect(BoardQuery.canDrop(card, on: .active) == false)
        #expect(BoardQuery.drop(card, on: .active, at: now, in: ctx) == false)
        #expect(card.status == .next)
        #expect(BoardQuery.canDrop(card, on: .next) == false)
        #expect(BoardQuery.canDrop(card, on: .idea))
        #expect(BoardQuery.canDrop(card, on: .done))
    }

    @Test func activeCardCanBeDroppedOnDone() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1", lastSeenAt: now)
        CardLifecycle.attach(card, s, at: now, in: ctx)
        #expect(BoardQuery.drop(card, on: .done, at: now + 1, in: ctx))
        #expect(card.status == .done)
        #expect(card.doneAt == now + 1)
        // 세션이 끝나도 done에 남는다
        CardLifecycle.detachAll(s, at: now + 2, in: ctx)
        #expect(card.status == .done)
    }

    /// 드래그 이동이 저장되는지: move → save → 새 context로 다시 읽는다.
    @Test func droppedStatusIsSaved() throws {
        let (container, ctx) = try makeContext()
        let p = try ledger(ctx)
        let card = try #require(p.cards?.first { $0.number == 15 })
        #expect(card.status == .next)
        #expect(BoardQuery.drop(card, on: .done, at: now, in: ctx))
        try ctx.save()

        let fresh = ModelContext(container)
        let id = card.id
        let reread = try #require(try fresh.fetch(FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.id == id })).first)
        #expect(reread.status == .done)
        #expect(reread.doneAt == now)
        let statusEvents = (reread.events ?? []).filter { $0.type == .cardStatus }
        #expect(statusEvents.contains { $0.payloadValues["to"]?.stringValue == "done" })
    }

    @Test func droppedStatusSurvivesReopeningFileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Board.store")
        let id: UUID
        do {
            let ctx = ModelContext(try WaypointStore.makeContainer(inMemory: false, url: url))
            let p = makeProject(ctx)
            let card = p.makeCard(in: ctx, title: "a", status: .idea, at: t0)
            id = card.id
            try ctx.save()
            #expect(BoardQuery.drop(card, on: .next, at: t0 + 1, in: ctx))
            try ctx.save()
        }
        let again = ModelContext(try WaypointStore.makeContainer(inMemory: false, url: url))
        let card = try #require(try again.fetch(FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.id == id })).first)
        #expect(card.status == .next)
    }

    @Test func primaryLinkPrefersLive() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let stalled = makeSession(ctx, p, id: "old", startedAt: t0, lastSeenAt: now - minutes(30))
        let live = makeSession(ctx, p, id: "new", startedAt: now - 60, lastSeenAt: now)
        CardLifecycle.attach(card, stalled, at: t0, in: ctx)
        CardLifecycle.attach(card, live, at: now - 60, in: ctx)
        #expect(BoardQuery.primaryLink(of: card, now: now)?.session === live)
        CardLifecycle.detach(card, live, at: now, in: ctx)
        #expect(BoardQuery.primaryLink(of: card, now: now)?.session === stalled)
    }

    @Test func sampleStatsMatchDesign() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let cards = try ledger(ctx).cards ?? []
        func stats(_ n: Int) throws -> CardWorkStats { BoardQuery.stats(of: try #require(cards.first { $0.number == n })) }
        #expect(try stats(14) == CardWorkStats(sessionCount: 1, subagentCount: 1, commitCount: 0))
        #expect(try stats(13) == CardWorkStats(sessionCount: 2, subagentCount: 0, commitCount: 3))
        #expect(try stats(11).sessionCount == 3)
        #expect(try stats(10).sessionCount == 1)
    }
}

/// 작업중 칸의 카드 없는 세션 타일.
@Suite struct BoardSessionTileTests {
    let now = t0 + 3600

    @Test func cardlessMainSessionsBecomeTiles() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let withCard = makeSession(ctx, p, id: "with-card", startedAt: t0 + 60, lastSeenAt: now)
        CardLifecycle.attach(card, withCard, at: t0 + 60, in: ctx)
        let live = makeSession(ctx, p, id: "live-none", startedAt: t0 + 120, lastSeenAt: now - 60)
        let stalled = makeSession(ctx, p, id: "stalled-none", startedAt: t0, lastSeenAt: now - minutes(20))
        let ended = makeSession(ctx, p, id: "ended-none", startedAt: t0, lastSeenAt: now)
        ended.endedAt = now
        // 서브에이전트: 끝나지 않은 둘(live·stalled), 끝난 하나
        makeSession(ctx, p, id: "sub-1", startedAt: t0 + 130, lastSeenAt: now, parent: live)
        makeSession(ctx, p, id: "sub-2", startedAt: t0 + 140, lastSeenAt: now - minutes(30), parent: live)
        makeSession(ctx, p, id: "sub-3", startedAt: t0 + 150, lastSeenAt: now, parent: live).endedAt = now - 10

        let tiles = BoardQuery.sessionTiles(for: p, now: now)
        // 세션 시작순, 카드가 붙은 세션·끝난 세션·서브에이전트는 타일이 아니다
        #expect(tiles.map(\.session.id) == ["stalled-none", "live-none"])
        #expect(tiles.map(\.workState) == [.stalled, .live])
        #expect(tiles.map(\.runningSubagents) == [0, 2])
        // 작업중 카드 칸은 그대로
        #expect((BoardQuery.columns(for: p, now: now)[.active] ?? []).map(\.card.id) == [card.id])
        // 대시보드 카드 없는 줄·작업중 개수와 같은 기준
        let dashboard = DashboardQuery.rows(for: p, now: now).filter { $0.card == nil }.map(\.session.id)
        #expect(dashboard == tiles.map(\.session.id))
        let summary = DashboardQuery.summary(for: p, now: now)
        #expect(summary.liveCount + summary.stalledCount == 1 + tiles.count)
    }

    @Test func tileDisappearsWhenCardAttachesOrSessionEnds() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let s = makeSession(ctx, p, id: "s1", lastSeenAt: now)
        #expect(BoardQuery.sessionTiles(for: p, now: now).count == 1)
        CardLifecycle.attach(card, s, at: now, in: ctx)
        #expect(BoardQuery.sessionTiles(for: p, now: now).isEmpty)
        CardLifecycle.detach(card, s, at: now + 1, in: ctx)
        #expect(BoardQuery.sessionTiles(for: p, now: now + 1).count == 1)
        s.endedAt = now + 2
        #expect(BoardQuery.sessionTiles(for: p, now: now + 2).isEmpty)
    }

    @Test func archivedProjectHasNoTiles() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        makeSession(ctx, p, id: "s1", lastSeenAt: now)
        p.archivedAt = now
        #expect(BoardQuery.sessionTiles(for: p, now: now).isEmpty)
    }
}
