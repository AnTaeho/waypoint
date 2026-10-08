import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-64: 여러 프로젝트 상황판의 타일 집계.

private let day: TimeInterval = 24 * 3600

private func session(
    _ ctx: ModelContext, _ project: Project, id: String, startedAt: Date, lastSeenAt: Date,
    provider: AgentProvider = .claude
) -> Session {
    let s = Session(id: id, startedAt: startedAt, lastSeenAt: lastSeenAt, provider: provider)
    ctx.insert(s)
    s.project = project
    return s
}

private func status(_ ctx: ModelContext, _ project: Project, _ text: String, at date: Date, provider: String = "claude") {
    Event.record(.projectStatus, in: ctx, project: project, at: date,
                 payload: ["summary": .string(text), "provider": .string(provider)])
}

@Suite struct ProjectSituationTests {
    @Test func sectionsAreCappedAndCounted() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 10 * day
        let next = (1...5).map { p.makeCard(in: ctx, title: "다음 \($0)", status: .next, at: t0) }
        _ = (1...2).map { p.makeCard(in: ctx, title: "아이디어 \($0)", status: .idea, at: t0) }
        for i in 0..<5 {
            let s = session(ctx, p, id: "s\(i)", startedAt: now - minutes(Double(10 - i)), lastSeenAt: now)
            CardLifecycle.attach(p.makeCard(in: ctx, title: "작업 \(i)", status: .next, at: t0), s, at: now - minutes(5), in: ctx)
        }
        for i in 0..<4 {
            let card = p.makeCard(in: ctx, title: "끝 \(i)", status: .next, at: t0)
            try CardLifecycle.move(card, to: .done, at: now - Double(i + 1) * 3600, in: ctx)
        }

        let tile = ProjectSituation.make(for: p, now: now, status: nil, unfiledCount: 0)
        #expect(tile.inProgress.map(\.card.title) == ["작업 0", "작업 1", "작업 2"])
        #expect(tile.inProgressCount == 5)
        #expect(tile.next.map(\.number) == next.prefix(3).map(\.number))
        #expect(tile.nextCount == 5)
        #expect(tile.recentDone.map(\.title) == ["끝 0", "끝 1", "끝 2"])
        #expect(tile.recentDoneCount == 4)
        #expect(tile.ideaCount == 2)
        #expect(tile.isLive)
    }

    /// 같은 카드에 세션 둘(Claude 멈춤, Codex live) → 한 줄, live, 도구 둘. 모두 멈추면 stalled.
    @Test func cardWithTwoSessionsIsOneLine() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + minutes(60)
        let card = p.makeCard(in: ctx, title: "a", status: .next, at: t0)
        let stalled = session(ctx, p, id: "old", startedAt: t0, lastSeenAt: t0)
        let live = session(ctx, p, id: "new", startedAt: t0 + 1, lastSeenAt: now, provider: .codex)
        CardLifecycle.attach(card, stalled, at: t0, in: ctx)
        CardLifecycle.attach(card, live, at: t0 + 1, in: ctx)

        let tile = ProjectSituation.make(for: p, now: now, status: nil, unfiledCount: 0)
        #expect(tile.inProgress.count == 1)
        #expect(tile.inProgress.first?.workState == .live)
        #expect(tile.inProgress.first?.providers == [.claude, .codex])

        let later = ProjectSituation.make(for: p, now: now + minutes(60), status: nil, unfiledCount: 0)
        #expect(later.inProgress.first?.workState == .stalled)
        #expect(!later.isLive)
    }

    /// 카드 없는 live 세션은 진행 중 줄이 되지 않지만 작업중 점은 켠다(사이드바 작업중 수와 같은 기준).
    @Test func cardlessSessionLightsDotOnly() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        _ = session(ctx, p, id: "free", startedAt: t0, lastSeenAt: t0)
        let tile = ProjectSituation.make(for: p, now: t0 + 1, status: nil, unfiledCount: 0)
        #expect(tile.inProgress.isEmpty)
        #expect(tile.isLive)
        #expect(DashboardQuery.summary(for: p, now: t0 + 1).liveCount == 1)
    }

    /// 완료 칸과 같은 경계: 딱 7일 전에 끝낸 것은 빠지고 그보다 1초 뒤는 들어간다.
    @Test func recentDoneWindowIsStrict() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 30 * day
        let edge = p.makeCard(in: ctx, title: "경계", status: .next, at: t0)
        let inside = p.makeCard(in: ctx, title: "안", status: .next, at: t0)
        try CardLifecycle.move(edge, to: .done, at: now - 7 * day, in: ctx)
        try CardLifecycle.move(inside, to: .done, at: now - 7 * day + 1, in: ctx)
        let tile = ProjectSituation.make(for: p, now: now, status: nil, unfiledCount: 0)
        #expect(tile.recentDone.map(\.title) == ["안"])
        #expect(tile.recentDoneCount == 1)
    }

    /// 최신 상황 글이 보이고, 7일을 넘으면 오래됨이다(딱 7일은 아직 아니다).
    @Test func latestStatusAndStaleness() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let other = makeProject(ctx, key: "OTH", name: "다른")
        status(ctx, p, "예전", at: t0)
        status(ctx, p, "지금", at: t0 + day, provider: "codex")
        status(ctx, other, "다른 프로젝트", at: t0 + 2 * day)

        let board = ProjectSituation.board(for: [p, other], now: t0 + 8 * day)
        let tile = try #require(board.first { $0.project === p })
        let entry = try #require(tile.status)
        #expect(entry.text == "지금")
        #expect(entry.provider == .codex)
        #expect(!entry.isStale(now: t0 + 8 * day))
        #expect(entry.isStale(now: t0 + 8 * day + 1))
        #expect(board.first { $0.project === other }?.status?.text == "다른 프로젝트")
        #expect(ProjectStatus.latestEntries(in: ctx)[p.id] == ProjectStatus.latest(for: p))
    }

    /// 작업 중인 프로젝트 먼저, 그다음 마지막 활동 최근순, 같으면 키순. 보관 프로젝트는 빠진다.
    @Test func boardOrderAndArchived() throws {
        let (c, ctx) = try makeContext(); _ = c
        let now = t0 + 10 * day
        let quiet = makeProject(ctx, key: "QUI", name: "조용")
        let recent = makeProject(ctx, key: "REC", name: "최근")
        let tie = makeProject(ctx, key: "AAA", name: "동률")
        let working = makeProject(ctx, key: "WRK", name: "작업")
        let archived = makeProject(ctx, key: "ARC", name: "보관")
        // 작업 중인 프로젝트보다 최근 활동이 늦어도 작업 중인 프로젝트가 먼저다.
        quiet.lastEventAt = now - 3 * day
        recent.lastEventAt = now + 60
        tie.lastEventAt = now + 60
        archived.lastEventAt = now
        archived.archivedAt = now
        let s = session(ctx, working, id: "w", startedAt: now - 9 * day, lastSeenAt: now - 9 * day)
        CardLifecycle.attach(working.makeCard(in: ctx, title: "a", status: .next, at: t0), s, at: now - 9 * day, in: ctx)
        s.lastSeenAt = now

        let board = ProjectSituation.board(for: [quiet, recent, tie, working, archived], now: now)
        #expect(board.map(\.project.key) == ["WRK", "AAA", "REC", "QUI"])
    }

    /// 정리 안 된 작업 수: 끝난 메인 세션이 카드 없이 파일을 바꾼 것만, 넘긴 세션은 빠진다.
    @Test func unfiledCount() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 20 * day
        for (i, id) in ["a", "b", "c"].enumerated() {
            let s = session(ctx, p, id: id, startedAt: now - day, lastSeenAt: now - Double(i) * 3600)
            s.endedAt = s.lastSeenAt
            Event.record(.fileChanged, in: ctx, project: p, session: s, at: s.lastSeenAt - 10, payload: ["path": "x.swift"])
        }
        Event.record(.sessionFiled, in: ctx, project: p, at: now, payload: ["sessionId": "c", "outcome": "dismissed"])
        let clean = session(ctx, p, id: "clean", startedAt: now - day, lastSeenAt: now - day)
        clean.endedAt = now - day

        #expect(ProjectSituation.board(for: [p], now: now).first?.unfiledCount == 2)
    }

    /// 도구 필터: 진행 중은 그 도구 세션이 붙은 카드만, 작업중 점도 그 도구로. 프로젝트는 그대로 남는다.
    /// 검색: 맞는 카드만 섹션에 남고 개수도 거른 뒤 센다.
    @Test func providerAndCardFilters() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + minutes(1)
        let claude = session(ctx, p, id: "cl", startedAt: t0, lastSeenAt: now)
        let codex = session(ctx, p, id: "cx", startedAt: t0 + 1, lastSeenAt: now, provider: .codex)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "클로드 일", status: .next, at: t0), claude, at: t0, in: ctx)
        CardLifecycle.attach(p.makeCard(in: ctx, title: "코덱스 일", status: .next, at: t0), codex, at: t0, in: ctx)
        _ = p.makeCard(in: ctx, title: "다음 검색", status: .next, at: t0)
        _ = p.makeCard(in: ctx, title: "다음 다른", status: .next, at: t0)

        let codexOnly = ProjectSituation.board(for: [p], now: now, provider: .codex)
        #expect(codexOnly.count == 1)
        #expect(codexOnly.first?.inProgress.map(\.card.title) == ["코덱스 일"])
        #expect(codexOnly.first?.nextCount == 2)

        // Claude 세션만 멈추면 Claude로 거른 타일은 작업중 점이 꺼진다.
        let later = t0 + minutes(30)
        codex.lastSeenAt = later
        #expect(!ProjectSituation.make(for: p, now: later, status: nil, unfiledCount: 0, provider: .claude).isLive)
        #expect(ProjectSituation.make(for: p, now: later, status: nil, unfiledCount: 0).isLive)
        codex.lastSeenAt = now

        let searched = ProjectSituation.board(for: [p], now: now) { _ in { $0.title.contains("검색") } }
        #expect(searched.first?.inProgress.isEmpty == true)
        #expect(searched.first?.next.map(\.title) == ["다음 검색"])
        #expect(searched.first?.nextCount == 1)
    }

    // 지금 상황 글은 빈 줄을 빼고 딱 8줄까지 받는다.
    @Test func statusTextAcceptsExactlyLineLimit() throws {
        let lines = (1...ProjectStatus.lineLimit).map { "줄 \($0)" }
        #expect(try ProjectStatus.normalized(lines.joined(separator: "\n\n")) == lines.joined(separator: "\n"))
        #expect(throws: MCPToolError.self) { try ProjectStatus.normalized((lines + ["줄 9"]).joined(separator: "\n")) }
    }

    // 저장소에 넣지 않은 프로젝트의 지금 상황은 상황 기록에서만 읽는다.
    @Test func latestStatusOutsideAStoreIgnoresOtherRecords() {
        let p = Project(key: "TMP", name: "임시", createdAt: t0)
        let status = Event(type: .projectStatus, at: t0, payload: EventValue.encode(["summary": "지금"]))
        let later = Event(type: .note, at: t0 + 60, payload: EventValue.encode(["summary": "메모"]))
        p.events = [status, later]
        #expect(ProjectStatus.latest(for: p)?.text == "지금")
    }
}

/// 실제 저장소 **사본**으로 상황판 집계 시간을 잰다. `WAYPOINT_REAL_STORE_COPY`(사본 `.store` 경로)가 있을 때만 돈다.
@Suite struct ProjectSituationTimingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"] != nil))
    func realStoreBoardTiming() throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-situation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Waypoint.store")
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let container = try WaypointStore.makeContainer(url: url)
        let ctx = ModelContext(container)
        let projects = try ctx.fetch(FetchDescriptor<Project>()).filter { $0.archivedAt == nil }
        let now = Date()

        func median(_ runs: Int, _ body: () -> Void) -> Double {
            let times = (0..<runs).map { _ -> Double in
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }.sorted()
            return times[times.count / 2]
        }
        _ = ProjectSituation.board(for: projects, now: now)  // 관계 적재(첫 회)
        let board = median(20) { _ = ProjectSituation.board(for: projects, now: now) }
        let summary = median(20) { for p in projects { _ = DashboardQuery.summary(for: p, now: now) } }
        let unfiledItems = median(20) { for p in projects { _ = UnfiledWork.items(for: p, now: now, limit: 0) } }
        let unfiledCount = median(20) { for p in projects { _ = UnfiledWork.count(for: p, now: now) } }
        let status = median(20) { _ = ProjectStatus.latestEntries(in: ctx) }
        let tiles = ProjectSituation.board(for: projects, now: now)
        for p in projects { #expect(UnfiledWork.count(for: p, now: now) == UnfiledWork.items(for: p, now: now).count) }
        print("[situation-timing] projects=\(projects.count) sessions=\(try ctx.fetchCount(FetchDescriptor<Session>())) "
              + "events=\(try ctx.fetchCount(FetchDescriptor<Event>())) "
              + String(format: "board=%.2fms summaryLoop=%.2fms unfiledItems=%.2fms unfiledCount=%.2fms status=%.2fms",
                       board, summary, unfiledItems, unfiledCount, status)
              + " live=\(tiles.filter(\.isLive).count) withStatus=\(tiles.filter { $0.status != nil }.count)"
              + " unfiledTotal=\(tiles.map(\.unfiledCount).reduce(0, +))")
        #expect(tiles.count == projects.count)
    }
}
