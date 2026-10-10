import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-72: 나를 기다리는 세션(승인·질문)을 프로젝트마다 센다.
@Suite struct SessionWaitingTests {
    private static let other = "9b1d0c52-0000-4000-8000-000000000002"

    private func send(_ h: HookHarness, _ event: String, at: Date, session: String = HookHarness.sessionID,
                      id: String? = nil, tool: String = "Bash", agent: String? = nil) throws {
        var object: [String: Any] = ["session_id": session, "cwd": "/Users/me/dev/ledger", "tool_name": tool, "prompt": "work"]
        if let id { object["tool_use_id"] = id }
        if let agent { object["agent_id"] = agent; object["agent_type"] = "test-writer" }
        h.processor.handle(try #require(HookInput(event: event, object: object)), at: at)
    }

    private func waiting(_ h: HookHarness, now: Date) -> SessionWaiting {
        ProjectSituation.make(for: h.project, now: now, status: nil, unfiledCount: 0).waiting
    }

    /// 승인을 기다리는 세션까지 보낸다.
    private func askApproval(_ h: HookHarness, session: String = HookHarness.sessionID, at: Date = t0) throws {
        try send(h, "SessionStart", at: at, session: session)
        try send(h, "UserPromptSubmit", at: at + 1, session: session)
        try send(h, "PreToolUse", at: at + 2, session: session, id: "a-\(session)")
        try send(h, "PermissionRequest", at: at + 3, session: session)
    }

    /// 질문을 띄운 세션까지 보낸다.
    private func askQuestion(_ h: HookHarness, session: String, tool: String = "AskUserQuestion", at: Date = t0) throws {
        try send(h, "SessionStart", at: at, session: session)
        try send(h, "UserPromptSubmit", at: at + 1, session: session)
        try send(h, "PreToolUse", at: at + 2, session: session, id: "q-\(session)", tool: tool)
    }

    @Test func approvalOnly() throws {
        let h = try HookHarness()
        try askApproval(h)
        #expect(waiting(h, now: t0 + 10) == SessionWaiting(approval: 1))
        #expect(waiting(h, now: t0 + 10).labels == ["승인 기다림 1"])
        // 오래 서 있어도 그대로 센다.
        #expect(waiting(h, now: t0 + minutes(60)) == SessionWaiting(approval: 1))
    }

    @Test func questionOnly() throws {
        let h = try HookHarness()
        try askQuestion(h, session: HookHarness.sessionID)
        #expect(waiting(h, now: t0 + 10) == SessionWaiting(question: 1))
        #expect(waiting(h, now: t0 + 10).labels == ["질문 기다림 1"])
        // 답하면(PostToolUse) 사라진다.
        try send(h, "PostToolUse", at: t0 + 20, id: "q-\(HookHarness.sessionID)", tool: "AskUserQuestion")
        #expect(waiting(h, now: t0 + 20).isEmpty)
    }

    @Test func codexQuestionToolCounts() throws {
        let h = try HookHarness()
        try askQuestion(h, session: HookHarness.sessionID, tool: "request_user_input")
        #expect(waiting(h, now: t0 + 10) == SessionWaiting(question: 1))
    }

    @Test func approvalAndQuestionSideBySide() throws {
        let h = try HookHarness()
        try askApproval(h)
        try askQuestion(h, session: Self.other)
        let both = waiting(h, now: t0 + 10)
        #expect(both == SessionWaiting(approval: 1, question: 1))
        #expect(both.labels == ["승인 기다림 1", "질문 기다림 1"])
    }

    /// 턴이 끝나거나 막 시작해 다음 요청을 기다리는 세션은 세지 않는다.
    @Test func plainInputWaitingIsNotCounted() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        #expect(waiting(h, now: t0).isEmpty)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "a")
        #expect(waiting(h, now: t0 + 2).isEmpty)
        try send(h, "PostToolUse", at: t0 + 3, id: "a")
        try send(h, "Stop", at: t0 + 4)
        let s = try #require(try h.session())
        #expect(SessionActivityRules.activity(s, now: t0 + 5) == .waiting)
        #expect(waiting(h, now: t0 + 5).isEmpty)
        #expect(waiting(h, now: t0 + 5).labels.isEmpty)
    }

    /// 질문을 띄운 채 턴이 끝나면(Stop) 떠 있는 도구가 지워져 세지 않는다.
    @Test func questionClearedByStop() throws {
        let h = try HookHarness()
        try askQuestion(h, session: HookHarness.sessionID)
        try send(h, "Stop", at: t0 + 5)
        #expect(waiting(h, now: t0 + 6).isEmpty)
    }

    @Test func endedSessionIsNotCounted() throws {
        let h = try HookHarness()
        try askApproval(h)
        try askQuestion(h, session: Self.other)
        let s = try #require(try h.session())
        h.processor.finish(s, at: t0 + 20, reason: "logout")
        #expect(waiting(h, now: t0 + 21) == SessionWaiting(question: 1))
        #expect(SessionWaiting.kind(of: s, now: t0 + 21) == nil)
    }

    @Test func approvalDisappearsWhenToolFinishes() throws {
        let h = try HookHarness()
        try askApproval(h)
        #expect(waiting(h, now: t0 + 4) == SessionWaiting(approval: 1))
        try send(h, "PostToolUse", at: t0 + 5, id: "a-\(HookHarness.sessionID)")
        #expect(waiting(h, now: t0 + 5).isEmpty)
    }

    /// 서브에이전트가 승인을 기다리면 그 세션 하나로 센다. 부모는 도구 작업 중이라 겹쳐 세지 않는다.
    @Test func waitingSubagentCountsOnce() throws {
        let h = try HookHarness()
        try send(h, "SessionStart", at: t0)
        try send(h, "UserPromptSubmit", at: t0 + 1)
        try send(h, "PreToolUse", at: t0 + 2, id: "agent", tool: "Agent")
        try send(h, "SubagentStart", at: t0 + 3, agent: HookHarness.agentID)
        try send(h, "PreToolUse", at: t0 + 4, id: "b", agent: HookHarness.agentID)
        #expect(waiting(h, now: t0 + 4).isEmpty)
        try send(h, "PermissionRequest", at: t0 + 5, agent: HookHarness.agentID)
        let parent = try #require(try h.session())
        let child = try #require(try h.session(HookHarness.agentID))
        #expect(child.kind == .subagent && child.parent === parent)
        #expect(SessionWaiting.kind(of: child, now: t0 + 6) == .approval)
        #expect(SessionWaiting.kind(of: parent, now: t0 + 6) == nil)
        #expect(waiting(h, now: t0 + 6) == SessionWaiting(approval: 1))
        try send(h, "PostToolUse", at: t0 + 7, id: "b", agent: HookHarness.agentID)
        #expect(waiting(h, now: t0 + 7).isEmpty)
    }

    /// 도구 필터를 고르면 그 도구 세션만 센다.
    @Test func providerFilterNarrowsCount() throws {
        let h = try HookHarness()
        try askApproval(h)
        let now = t0 + 10
        #expect(ProjectSituation.make(for: h.project, now: now, status: nil, unfiledCount: 0, provider: .claude).waiting.approval == 1)
        #expect(ProjectSituation.make(for: h.project, now: now, status: nil, unfiledCount: 0, provider: .codex).waiting.isEmpty)
    }

    /// 순서: 나를 기다리는 프로젝트, 작업 중인 프로젝트, 그다음 최근 활동순.
    @Test func waitingProjectComesFirst() throws {
        let (c, ctx) = try makeContext(); _ = c
        let now = t0 + minutes(5)
        let quiet = makeProject(ctx, key: "AAA", name: "조용함")
        let busy = makeProject(ctx, key: "BBB", name: "작업 중")
        let blocked = makeProject(ctx, key: "CCC", name: "기다림")
        let working = makeSession(ctx, busy, id: "busy", startedAt: t0, lastSeenAt: now)
        working.activityRaw = SessionActivity.working.rawValue
        // 기다리는 쪽의 마지막 활동이 더 오래됐어도 앞에 온다.
        let asking = makeSession(ctx, blocked, id: "blocked", startedAt: t0, lastSeenAt: t0)
        asking.activityRaw = SessionActivity.approval.rawValue
        try ctx.save()

        let tiles = ProjectSituation.board(for: [quiet, busy, blocked], now: now)
        #expect(tiles.map(\.project.key) == ["CCC", "BBB", "AAA"])
        #expect(tiles[0].waiting == SessionWaiting(approval: 1) && !tiles[0].isLive)
        #expect(tiles[1].waiting.isEmpty && tiles[1].isLive)
    }
}
