import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 대시보드 위 집계·머리말·「확인하고 이어가기」·사이드바가 내 답을 기다리는 세션을 따로 본다(TRK-72 후속).
@Suite struct DashboardWaitingTests {
    private static let asking = "9b1d0c52-0000-4000-8000-000000000002"
    private static let resting = "9b1d0c52-0000-4000-8000-000000000003"
    private static let busy = "9b1d0c52-0000-4000-8000-000000000004"

    private func send(_ h: HookHarness, _ event: String, at: Date, session: String, id: String? = nil,
                      tool: String = "Bash") throws {
        var object: [String: Any] = ["session_id": session, "cwd": "/Users/me/dev/ledger", "tool_name": tool, "prompt": "work"]
        if let id { object["tool_use_id"] = id }
        h.processor.handle(try #require(HookInput(event: event, object: object)), at: at)
    }

    private func start(_ h: HookHarness, _ session: String, at: Date) throws {
        try send(h, "SessionStart", at: at, session: session)
        try send(h, "UserPromptSubmit", at: at + 1, session: session)
    }

    /// 승인 1(기본 세션) · 질문 1 · 턴이 끝나 쉬는 세션 1 · 도구 작업 중 1. 세션 시작순도 이 순서.
    private func scene() throws -> HookHarness {
        let h = try HookHarness()
        try start(h, HookHarness.sessionID, at: t0)
        try send(h, "PreToolUse", at: t0 + 2, session: HookHarness.sessionID, id: "a")
        try send(h, "PermissionRequest", at: t0 + 3, session: HookHarness.sessionID)
        try start(h, Self.asking, at: t0 + 10)
        try send(h, "PreToolUse", at: t0 + 12, session: Self.asking, id: "q", tool: "AskUserQuestion")
        try start(h, Self.resting, at: t0 + 20)
        try send(h, "Stop", at: t0 + 22, session: Self.resting)
        try start(h, Self.busy, at: t0 + 30)
        try send(h, "PreToolUse", at: t0 + 32, session: Self.busy, id: "w")
        return h
    }

    @Test func waitingRowsLeaveStalledCountAndAreCountedApart() throws {
        let h = try scene()
        let overview = DashboardOverview(projects: [h.project], now: t0 + 40)
        #expect(overview.liveCount == 1)
        #expect(overview.waitingCount == 2)
        #expect(overview.stalledCount == 1)
        // 판정은 그대로다: 기다리는 줄도 멈춘 줄이다.
        let rows = overview.groups.flatMap(\.rows)
        #expect(rows.filter { $0.workState == .stalled }.count == 3)
        #expect(rows.map(\.waitingKind) == [.approval, .question, nil, nil])
    }

    /// 턴이 끝나 쉬는 입력 대기는 15분이 지나도 「대기·활동 없음」에 남는다.
    @Test func plainRestingSessionStaysStalled() throws {
        let h = try HookHarness()
        try start(h, Self.resting, at: t0)
        try send(h, "Stop", at: t0 + 2, session: Self.resting)
        for now in [t0 + 3, t0 + minutes(60)] {
            let overview = DashboardOverview(projects: [h.project], now: now)
            #expect(overview.waitingCount == 0 && overview.stalledCount == 1 && overview.liveCount == 0)
        }
    }

    @Test func endedWaitingSessionIsNotCounted() throws {
        let h = try scene()
        h.processor.finish(try #require(try h.session()), at: t0 + 35, reason: "logout")
        let overview = DashboardOverview(projects: [h.project], now: t0 + 40)
        #expect(overview.waitingCount == 1 && overview.stalledCount == 1 && overview.liveCount == 1)
    }

    /// 답하면(도구가 끝나면) 기다림에서 빠져 작업 중으로 간다.
    @Test func answeredSessionGoesBackToLive() throws {
        let h = try scene()
        try send(h, "PostToolUse", at: t0 + 36, session: HookHarness.sessionID, id: "a")
        let overview = DashboardOverview(projects: [h.project], now: t0 + 40)
        #expect(overview.waitingCount == 1 && overview.liveCount == 2 && overview.stalledCount == 1)
    }

    /// 같은 세션이 카드 둘에 붙어 있으면 줄 수대로 센다(옆 칸과 같은 단위).
    @Test func waitingCountsRowsLikeNeighbours() throws {
        let h = try scene()
        let session = try #require(try h.session())
        for title in ["one", "two"] {
            CardLifecycle.attach(h.project.makeCard(in: h.context, title: title, at: t0), session, at: t0 + 4, in: h.context)
        }
        #expect(DashboardOverview(projects: [h.project], now: t0 + 40).waitingCount == 3)
    }

    @Test func splitKeepsRowOrderAndDropsLiveRows() throws {
        let h = try scene()
        let rows = DashboardQuery.rows(for: h.project, now: t0 + 40)
        let held = DashboardOverview.split(rows)
        #expect(held.waiting.map(\.session.id) == [HookHarness.sessionID, Self.asking])
        #expect(held.waiting.map(\.waitingKind) == [.approval, .question])
        #expect(held.resting.map(\.session.id) == [Self.resting])
        #expect(DashboardOverview.split([]).waiting.isEmpty && DashboardOverview.split([]).resting.isEmpty)
    }

    /// 도구 필터로 거른 줄만 가른다(화면이 거른 뒤 부른다).
    @Test func splitFollowsProviderFilter() throws {
        let h = try scene()
        try #require(try h.session(Self.asking)).providerRaw = AgentProvider.codex.rawValue
        let rows = DashboardQuery.rows(for: h.project, now: t0 + 40)
        let claude = DashboardOverview.split(rows.filter { $0.session.provider == .claude })
        let codex = DashboardOverview.split(rows.filter { $0.session.provider == .codex })
        #expect(claude.waiting.map(\.session.id) == [HookHarness.sessionID])
        #expect(claude.resting.map(\.session.id) == [Self.resting])
        #expect(codex.waiting.map(\.session.id) == [Self.asking] && codex.resting.isEmpty)
    }

    @Test func headlineCases() {
        #expect(DashboardOverview.headline(liveProjects: 2, waiting: 0) == "2개 프로젝트에서 작업 중입니다.")
        #expect(DashboardOverview.headline(liveProjects: 0, waiting: 3) == "3개 세션이 내 답을 기다립니다.")
        #expect(DashboardOverview.headline(liveProjects: 1, waiting: 2) == "1개 프로젝트에서 작업 중, 2개 세션이 내 답을 기다립니다.")
        #expect(DashboardOverview.headline(liveProjects: 0, waiting: 0) == "진행 중인 작업이 없습니다.")
    }

    @Test func overviewHeadlineUsesItsCounts() throws {
        let h = try scene()
        #expect(DashboardOverview(projects: [h.project], now: t0 + 40).headline
            == "1개 프로젝트에서 작업 중, 2개 세션이 내 답을 기다립니다.")
    }

    /// 줄의 글: 승인과 질문을 다른 말로, 기다리기 시작한 때부터.
    @Test func waitingTextNamesKindAndElapsed() throws {
        let h = try scene()
        let approval = try #require(try h.session()), question = try #require(try h.session(Self.asking))
        #expect(SessionWaiting.text(.approval, session: approval, now: t0 + 3 + minutes(3)) == "승인 대기 3분")
        #expect(SessionWaiting.text(.question, session: question, now: t0 + 12 + minutes(5)) == "질문 대기 5분")
    }

    /// 사이드바: 멈춤 수는 그대로, 기다리는 세션 수만 따로 알려 준다.
    @Test func summaryReportsWaitingWithoutChangingCounts() throws {
        let h = try scene()
        let summary = DashboardQuery.summary(for: h.project, now: t0 + 40)
        #expect(summary.liveCount == 1 && summary.stalledCount == 3 && summary.waitingCount == 2)
        let quiet = try HookHarness()
        try start(quiet, Self.resting, at: t0)
        try send(quiet, "Stop", at: t0 + 2, session: Self.resting)
        let rest = DashboardQuery.summary(for: quiet.project, now: t0 + 40)
        #expect(rest.stalledCount == 1 && rest.waitingCount == 0)
    }
}
