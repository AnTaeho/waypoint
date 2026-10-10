import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-72 후속: 서브에이전트의 기다림을 부모 줄에 올리고, 도는 서브에이전트에 가려진 메인의 기다림도 잡는다.
@Suite struct WaitingGapsTests {
    private static let other = "9b1d0c52-0000-4000-8000-000000000002"
    private static let secondAgent = "b7e1c8f1e0b3a298"

    private func send(_ h: HookHarness, _ event: String, at: Date, session: String = HookHarness.sessionID,
                      id: String? = nil, tool: String = "Bash", agent: String? = nil) throws {
        var object: [String: Any] = ["session_id": session, "cwd": "/Users/me/dev/ledger", "tool_name": tool, "prompt": "work"]
        if let id { object["tool_use_id"] = id }
        if let agent { object["agent_id"] = agent; object["agent_type"] = "test-writer" }
        h.processor.handle(try #require(HookInput(event: event, object: object)), at: at)
    }

    /// 메인이 서브에이전트를 띄운 데까지(t0 + 3).
    private func spawn(_ h: HookHarness) throws {
        try send(h, "SessionStart", at: t0)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "agent", tool: "Agent")
        try send(h, "SubagentStart", at: t0 + 3, agent: HookHarness.agentID)
    }

    /// 서브에이전트가 승인을 기다리는 데까지(t0 + 5).
    private func childAsks(_ h: HookHarness) throws {
        try spawn(h)
        try send(h, "PreToolUse", at: t0 + 4, id: "b", agent: HookHarness.agentID)
        try send(h, "PermissionRequest", at: t0 + 5, agent: HookHarness.agentID)
    }

    private struct Seen: Equatable {
        var pill: Int, top: Int, bundle: Int, live: Int, resting: Int
        var headline: String
    }

    /// 알약(세션 수), 위 집계, 오른쪽 묶음, 작업 중, 대기·활동 없음, 머리말.
    private func seen(_ h: HookHarness, now: Date) -> Seen {
        let overview = DashboardOverview(projects: [h.project], now: now)
        let rows = overview.groups.flatMap(\.rows)
        return Seen(pill: ProjectSituation.make(for: h.project, now: now, status: nil, unfiledCount: 0).waiting.total,
                    top: overview.waitingCount, bundle: DashboardOverview.split(rows).waiting.count,
                    live: overview.liveCount, resting: overview.stalledCount, headline: overview.headline)
    }

    private let oneWaiting = Seen(pill: 1, top: 1, bundle: 1, live: 0, resting: 0, headline: "1개 세션이 내 답을 기다립니다.")
    private let oneLive = Seen(pill: 0, top: 0, bundle: 0, live: 1, resting: 0, headline: "1개 프로젝트에서 작업 중입니다.")

    // MARK: - 경우 표

    @Test func mainApproval() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "a")
        try send(h, "PermissionRequest", at: t0 + 3)
        #expect(seen(h, now: t0 + 10) == oneWaiting)
    }

    /// 카드 붙은 서브에이전트는 제 줄에서 한 번만 잡힌다. 부모 줄은 작업 중으로 남는다.
    @Test func cardedSubagentApprovalCountsOnceOnItsOwnRow() throws {
        let h = try HookHarness()
        try childAsks(h)
        let child = try #require(try h.session(HookHarness.agentID))
        CardLifecycle.attach(h.project.makeCard(in: h.context, title: "one", at: t0), child, at: t0 + 3, in: h.context)
        #expect(seen(h, now: t0 + 10) == Seen(pill: 1, top: 1, bundle: 1, live: 1, resting: 0,
                                              headline: "1개 프로젝트에서 작업 중, 1개 세션이 내 답을 기다립니다."))
        let rows = DashboardQuery.rows(for: h.project, now: t0 + 10)
        #expect(rows.map(\.session.id) == [HookHarness.sessionID, HookHarness.agentID])
        #expect(rows.map(\.waitingKind) == [nil, .approval])
        #expect(rows[1].waiting?.agentName == nil)
    }

    /// 카드 없는 서브에이전트는 줄이 없다. 부모 줄에 올려 한 번 잡는다.
    @Test func cardlessSubagentApprovalLiftsToParentRow() throws {
        let h = try HookHarness()
        try childAsks(h)
        #expect(seen(h, now: t0 + 10) == oneWaiting)
        let rows = DashboardQuery.rows(for: h.project, now: t0 + 10)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.session.id == HookHarness.sessionID && row.workState == .stalled && row.waitingKind == .approval)
        #expect(row.waiting?.session.id == HookHarness.agentID)
        // 서브에이전트가 기다리기 시작한 때부터 재고 이름을 곁들인다.
        #expect(row.waiting?.text(now: t0 + 5 + minutes(3)) == "승인 대기 3분 · test-writer")
        // 판정은 그대로다: 부모 세션은 도구 작업 중.
        #expect(SessionRules.state(of: row.session, now: t0 + 10) == .live)
        #expect(SessionWaiting.kind(of: row.session, now: t0 + 10) == nil)
    }

    @Test func liftedApprovalLeavesWhenChildToolFinishes() throws {
        let h = try HookHarness()
        try childAsks(h)
        try send(h, "PostToolUse", at: t0 + 7, id: "b", agent: HookHarness.agentID)
        #expect(seen(h, now: t0 + 8) == oneLive)
    }

    @Test func liftedApprovalLeavesWhenSubagentStops() throws {
        let h = try HookHarness()
        try childAsks(h)
        try send(h, "SubagentStop", at: t0 + 7, agent: HookHarness.agentID)
        #expect(seen(h, now: t0 + 8) == oneLive)
    }

    /// 메인이 승인을 기다리는데 먼저 띄운 서브에이전트가 돌고 있다. 활동은 도구 작업 중이어도 기다림으로 잡는다.
    @Test func mainApprovalBehindRunningSubagent() throws {
        let h = try HookHarness()
        try spawn(h)
        try send(h, "PreToolUse", at: t0 + 4, id: "c", agent: HookHarness.agentID)
        try send(h, "PreToolUse", at: t0 + 5, id: "a")
        try send(h, "PermissionRequest", at: t0 + 6)
        let main = try #require(try h.session())
        #expect(SessionActivityRules.activity(main, now: t0 + 10) == .toolRunning)
        #expect(SessionWaiting.kind(of: main, now: t0 + 10) == .approval)
        #expect(seen(h, now: t0 + 10) == oneWaiting)
        #expect(DashboardQuery.rows(for: h.project, now: t0 + 10).first?.waiting?.agentName == nil)
        // 승인하면(도구가 끝나면) 사라진다.
        try send(h, "PostToolUse", at: t0 + 11, id: "a")
        #expect(seen(h, now: t0 + 12) == oneLive)
    }

    /// 메인이 질문을 띄웠는데 서브에이전트가 돌고 있어도 질문으로 잡는다.
    @Test func mainQuestionBehindRunningSubagent() throws {
        let h = try HookHarness()
        try spawn(h)
        try send(h, "PreToolUse", at: t0 + 4, id: "c", agent: HookHarness.agentID)
        try send(h, "PreToolUse", at: t0 + 5, id: "q", tool: "AskUserQuestion")
        #expect(SessionWaiting.kind(of: try #require(try h.session()), now: t0 + 10) == .question)
        #expect(seen(h, now: t0 + 10) == oneWaiting)
    }

    /// 서브에이전트 띄우기를 승인받은 뒤다. 승인 뒤에 시작한 서브에이전트가 돌면 낡은 승인으로 보고 세지 않는다.
    @Test func approvalGrantedBeforeSubagentStartIsNotWaiting() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "agent", tool: "Agent")
        try send(h, "PermissionRequest", at: t0 + 3, tool: "Agent")
        #expect(seen(h, now: t0 + 3) == oneWaiting)
        try send(h, "SubagentStart", at: t0 + 4, agent: HookHarness.agentID)
        try send(h, "PreToolUse", at: t0 + 5, id: "c", agent: HookHarness.agentID)
        let main = try #require(try h.session())
        #expect(main.activityRaw == SessionActivity.approval.rawValue)
        #expect(SessionWaiting.kind(of: main, now: t0 + minutes(10)) == nil)
        #expect(seen(h, now: t0 + minutes(10)) == oneLive)
    }

    // MARK: - 두 번 세지 않음

    /// 부모가 카드 둘에 붙어 있어도 서브에이전트에게서 올린 기다림은 첫 줄 하나에만 든다.
    @Test func liftedWaitingSitsOnFirstParentRowOnly() throws {
        let h = try HookHarness()
        try childAsks(h)
        let main = try #require(try h.session())
        for (offset, title) in ["one", "two"].enumerated() {
            CardLifecycle.attach(h.project.makeCard(in: h.context, title: title, at: t0), main,
                                 at: t0 + 1 + Double(offset) / 10, in: h.context)
        }
        let rows = DashboardQuery.rows(for: h.project, now: t0 + 10)
        #expect(rows.map { $0.card?.title } == ["one", "two"])
        #expect(rows.map(\.waitingKind) == [.approval, nil])
        #expect(rows.map(\.workState) == [.stalled, .live])
        let s = seen(h, now: t0 + 10)
        #expect(s.pill == 1 && s.top == 1 && s.bundle == 1 && s.live == 1)
    }

    /// 카드 없는 서브에이전트 둘이 기다리면 줄은 하나(가장 오래 기다린 쪽), 알약은 세션 수대로 둘.
    @Test func twoCardlessChildrenShareOneRow() throws {
        let h = try HookHarness()
        try childAsks(h)
        try send(h, "SubagentStart", at: t0 + 6, agent: Self.secondAgent)
        try send(h, "PermissionRequest", at: t0 + 8, agent: Self.secondAgent)
        let s = seen(h, now: t0 + 10)
        #expect(s.pill == 2 && s.top == 1 && s.bundle == 1 && s.live == 0)
        let row = try #require(DashboardQuery.rows(for: h.project, now: t0 + 10).first)
        #expect(row.waiting?.session.id == HookHarness.agentID)
        // 먼저 기다린 쪽이 풀리면 다음 것이 올라온다.
        try send(h, "PostToolUse", at: t0 + 9, id: "b", agent: HookHarness.agentID)
        let next = try #require(DashboardQuery.rows(for: h.project, now: t0 + 10).first)
        #expect(next.waiting?.session.id == Self.secondAgent && seen(h, now: t0 + 10).pill == 1)
    }

    // MARK: - 보드·카드·메뉴 막대

    @Test func boardTileCarriesLiftedWaiting() throws {
        let h = try HookHarness()
        try childAsks(h)
        let tile = try #require(BoardQuery.sessionTiles(for: h.project, now: t0 + 10).first)
        #expect(tile.workState == .stalled && tile.waiting?.kind == .approval)
        #expect(tile.waiting?.text(now: t0 + 5 + minutes(2)) == "승인 대기 2분 · test-writer")
        try send(h, "PostToolUse", at: t0 + 11, id: "b", agent: HookHarness.agentID)
        let after = try #require(BoardQuery.sessionTiles(for: h.project, now: t0 + 12).first)
        #expect(after.workState == .live && after.waiting == nil)
    }

    /// 보드 카드: 붙은 세션이나 그 카드 없는 서브에이전트가 기다리면 그 기다림.
    @Test func cardShowsWaitingOfItsSessions() throws {
        let h = try HookHarness()
        try childAsks(h)
        let card = h.project.makeCard(in: h.context, title: "one", at: t0)
        #expect(SessionWaiting.shown(for: card, now: t0 + 10) == nil)
        CardLifecycle.attach(card, try #require(try h.session()), at: t0 + 1, in: h.context)
        let shown = try #require(SessionWaiting.shown(for: card, now: t0 + 10))
        #expect(shown.kind == .approval && shown.agentName == "test-writer")
        try send(h, "SubagentStop", at: t0 + 11, agent: HookHarness.agentID)
        #expect(SessionWaiting.shown(for: card, now: t0 + 12) == nil)
    }

    /// 상황판 타일의 진행 중 줄: 카드에 붙은 세션의 기다림을 싣고, 풀리면 비운다.
    @Test func situationWorkItemCarriesWaiting() throws {
        let h = try HookHarness()
        try childAsks(h)
        CardLifecycle.attach(h.project.makeCard(in: h.context, title: "one", at: t0), try #require(try h.session()),
                             at: t0 + 1, in: h.context)
        func item(_ now: Date) throws -> ProjectSituation.WorkItem {
            try #require(ProjectSituation.make(for: h.project, now: now, status: nil, unfiledCount: 0).inProgress.first)
        }
        let waiting = try item(t0 + 10)
        #expect(waiting.workState == .stalled)
        #expect(waiting.waiting?.text(now: t0 + 5 + minutes(3)) == "승인 대기 3분 · test-writer")
        try send(h, "PostToolUse", at: t0 + 11, id: "b", agent: HookHarness.agentID)
        let after = try item(t0 + 12)
        #expect(after.workState == .live && after.waiting == nil)
    }

    /// 좁은 줄의 글은 에이전트 이름을 뺀다. 긴 글에는 남는다.
    @Test func shortTextDropsAgentName() throws {
        let h = try HookHarness()
        try childAsks(h)
        let shown = try #require(DashboardQuery.rows(for: h.project, now: t0 + 10).first?.waiting)
        #expect(shown.agentName == "test-writer")
        #expect(shown.shortText(now: t0 + 5 + minutes(3)) == "승인 대기 3분")
        #expect(shown.text(now: t0 + 5 + minutes(3)) == "승인 대기 3분 · test-writer")
    }

    // MARK: - 사이드바 표시

    private func mark(_ h: HookHarness, now: Date) -> ProjectSummary.SidebarMark? {
        DashboardQuery.summary(for: h.project, now: now).sidebarMark
    }

    @Test func sidebarMarkIsNilWithoutSessions() throws {
        #expect(mark(try HookHarness(), now: t0 + 10) == nil)
    }

    @Test func sidebarMarkLiveThenStalled() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "a")
        #expect(mark(h, now: t0 + 3) == .live(1))
        try send(h, "PostToolUse", at: t0 + 4, id: "a")
        try send(h, "Stop", at: t0 + 5)
        #expect(mark(h, now: t0 + 10) == .stalled(1))
    }

    @Test func sidebarMarkWaitingWhenMainAsks() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "a")
        try send(h, "PermissionRequest", at: t0 + 3)
        #expect(mark(h, now: t0 + 10) == .waiting(1))
    }

    /// 부모는 도는 중이고 서브에이전트만 승인을 기다려도 기다림이 먼저다. 풀리면 작업중으로 돌아간다.
    @Test func sidebarMarkPutsSubagentWaitingBeforeLiveParent() throws {
        let h = try HookHarness()
        try childAsks(h)
        let main = try #require(try h.session())
        CardLifecycle.attach(h.project.makeCard(in: h.context, title: "one", at: t0), main, at: t0 + 1, in: h.context)
        #expect(SessionRules.state(of: main, now: t0 + 10) == .live)
        #expect(mark(h, now: t0 + 10) == .waiting(1))
        try send(h, "PostToolUse", at: t0 + 11, id: "b", agent: HookHarness.agentID)
        #expect(mark(h, now: t0 + 12) == .live(1))
    }

    /// 기다림·작업중·멈춤이 섞이면 기다리는 세션 수만 보인다.
    @Test func sidebarMarkOrder() {
        func mark(live: Int, stalled: Int, waiting: Int) -> ProjectSummary.SidebarMark? {
            ProjectSummary(liveCount: live, stalledCount: stalled, nextCount: 0, ideaCount: 0, lastActivityAt: nil,
                           waitingCount: waiting).sidebarMark
        }
        #expect(mark(live: 2, stalled: 3, waiting: 4) == .waiting(4))
        #expect(mark(live: 2, stalled: 3, waiting: 0) == .live(2))
        #expect(mark(live: 0, stalled: 3, waiting: 0) == .stalled(3))
        #expect(mark(live: 0, stalled: 0, waiting: 0) == nil)
    }

    /// 메뉴 막대: 질문 대기를 따로 세고 「입력 대기」에는 쉬는 세션만 남긴다.
    @Test func menuLineSplitsQuestionFromResting() throws {
        let h = try HookHarness()
        let ids = (2...5).map { "9b1d0c52-0000-4000-8000-00000000000\($0)" }
        for (index, id) in ([HookHarness.sessionID] + ids).enumerated() {
            try send(h, "SessionStart", at: t0 + Double(index), session: id)
            try send(h, "UserPromptSubmit", at: t0 + Double(index) + 0.5, session: id)
        }
        try send(h, "PreToolUse", at: t0 + 10, id: "a")
        try send(h, "PermissionRequest", at: t0 + 11)
        try send(h, "PreToolUse", at: t0 + 12, session: ids[0], id: "q", tool: "AskUserQuestion")
        try send(h, "Stop", at: t0 + 13, session: ids[1])
        try send(h, "Stop", at: t0 + 14, session: ids[2])
        try send(h, "PreToolUse", at: t0 + 15, session: ids[3], id: "w")
        let sessions = try h.context.fetch(FetchDescriptor<Session>()).filter { $0.kind == .main }
        #expect(SessionFormat.menuLine(name: "가계부 앱", sessions: sessions, now: t0 + 20)
            == "가계부 앱 · 도구 작업 중 1 · 입력 대기 2 · 승인 대기 1 · 질문 대기 1")
        #expect(SessionFormat.menuLine(name: "가계부 앱", sessions: [], now: t0 + 20) == nil)
    }

    /// 메뉴 막대도 카드 없는 서브에이전트의 승인 대기를 메인 세션 자리에서 센다.
    @Test func menuLineCountsLiftedApproval() throws {
        let h = try HookHarness()
        try childAsks(h)
        let main = try #require(try h.session())
        #expect(SessionFormat.menuLine(name: "가계부 앱", sessions: [main], now: t0 + 10) == "가계부 앱 · 승인 대기 1")
        try send(h, "PostToolUse", at: t0 + 11, id: "b", agent: HookHarness.agentID)
        #expect(SessionFormat.menuLine(name: "가계부 앱", sessions: [main], now: t0 + 12) == "가계부 앱 · 도구 작업 중 1")
    }
}
