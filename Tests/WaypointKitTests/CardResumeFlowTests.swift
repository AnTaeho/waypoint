import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-12: 준비됨/복사함/연결됨 구분과 도구 전환·시작 폴더·카드 상태 변경. 연결은 실제 MCP 경로(session_bind → card_start)로 만든다.
@Suite struct CardResumeFlowTests {
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let app: Project
        let other: Project
        let card: Card

        init() throws {
            (container, context) = try makeContext()
            app = makeProject(context, key: "APP"); app.rootPath = "/work/app"
            other = makeProject(context, key: "OTH"); other.rootPath = "/work/other"
            card = app.makeCard(in: context, title: "resume", status: .next, at: t0)
        }

        func call(_ name: String, _ args: JSONValue, at date: Date) throws -> JSONValue {
            try MCPTools(context: context, now: { date }).call(name, args)
        }

        /// 새 세션이 `cwd`에서 시작해 `project`로 연결되고 카드를 시작한다(재개 문맥이 안내하는 순서).
        func resume(_ id: String, _ provider: AgentProvider, project: Project, cwd: String, at date: Date) throws {
            _ = try call("session_bind", ["project": .string(project.key), "sessionId": .string(id),
                                          "provider": .string(provider.rawValue), "cwd": .string(cwd)], at: date)
            _ = try call("card_start", ["id": .string(card.displayID), "sessionId": .string(id)], at: date)
        }
    }

    @Test func readyCopiedConnectedAreDistinctAndCopyAloneNeverConnects() throws {
        let env = try Env()
        #expect(CardResumeStatus.of(env.card, attempt: nil) == .ready)
        let attempt = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 1)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .copied(.claude))
        #expect(env.card.status == .next)
        try env.resume("new", .claude, project: env.app, cwd: "/work/app", at: t0 + 2)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .connected(.claude))
        #expect(CardResumeStatus.of(env.card, attempt: attempt).label == "연결됨 · Claude Code 새 세션")
        #expect(CardResumeStatus.copied(.codex).label == "복사함 · Codex 새 세션 연결 전")
    }

    @Test func claudeToCodexSwitchCountsOnlyTheChosenToolsNewSession() throws {
        let env = try Env()
        let claudeAttempt = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 1)
        let codexAttempt = CardResumeAttempt(card: env.card, provider: .codex, at: t0 + 2)
        try env.resume("claude-new", .claude, project: env.app, cwd: "/work/app", at: t0 + 3)
        #expect(CardResumeStatus.of(env.card, attempt: codexAttempt) == .copied(.codex))
        #expect(CardResumeStatus.of(env.card, attempt: claudeAttempt) == .connected(.claude))
        try env.resume("codex:thread-1", .codex, project: env.app, cwd: "/work/app", at: t0 + 4)
        #expect(CardResumeStatus.of(env.card, attempt: codexAttempt) == .connected(.codex))
        // 다시 Claude로 바꿔 복사하면 이미 붙어 있던 세션은 새 세션이 아니다.
        let back = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 5)
        #expect(CardResumeStatus.of(env.card, attempt: back) == .copied(.claude))
    }

    @Test func sessionStartedInSubfolderConnects() throws {
        let env = try Env()
        let attempt = CardResumeAttempt(card: env.card, provider: .codex, at: t0 + 1)
        try env.resume("codex:sub", .codex, project: env.app, cwd: "/work/app/Sources/Feature", at: t0 + 2)
        #expect(attempt.state(for: env.card) == .connected)
    }

    @Test func sessionFromAnotherProjectFolderConnectsOnlyAfterBindingHere() throws {
        let env = try Env()
        let attempt = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 1)
        _ = try env.call("session_bind", ["project": "OTH", "sessionId": "elsewhere", "provider": "claude",
                                          "cwd": "/work/other"], at: t0 + 2)
        #expect(throws: MCPToolError.self) {
            try env.call("card_start", ["id": .string(env.card.displayID), "sessionId": "elsewhere"], at: t0 + 3)
        }
        #expect(attempt.state(for: env.card) == .waiting && env.card.status == .next)
        try env.resume("elsewhere", .claude, project: env.app, cwd: "/work/other", at: t0 + 4)
        #expect(attempt.state(for: env.card) == .connected)
        // 연결 뒤 다른 프로젝트로 옮겨 가면 카드 연결이 풀리고, 그 세션은 더 이상 이 프로젝트의 재개로 치지 않는다.
        _ = try env.call("session_bind", ["project": "OTH", "sessionId": "elsewhere", "provider": "claude",
                                          "cwd": "/work/other"], at: t0 + 5)
        #expect(env.card.openCardSessions.isEmpty)
        #expect(attempt.state(for: env.card) == .waiting)
    }

    @Test func otherCardSessionsAndPastIDsDoNotConnect() throws {
        let env = try Env()
        let past = makeSession(env.context, env.app, id: "past")
        CardLifecycle.attach(env.card, past, at: t0, in: env.context)
        CardLifecycle.detach(env.card, past, at: t0 + 1, in: env.context)
        let attempt = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 2)
        // 과거 ID로 다시 붙어도 새 세션이 아니다.
        _ = try env.call("card_start", ["id": .string(env.card.displayID), "sessionId": "past"], at: t0 + 3)
        #expect(attempt.state(for: env.card) == .waiting)
        // 다른 카드에 붙은 새 세션은 이 카드의 재개가 아니다.
        let otherCard = env.app.makeCard(in: env.context, title: "other", status: .next, at: t0)
        _ = try env.call("session_bind", ["project": "APP", "sessionId": "busy", "provider": "claude",
                                          "cwd": "/work/app"], at: t0 + 4)
        _ = try env.call("card_start", ["id": .string(otherCard.displayID), "sessionId": "busy"], at: t0 + 4)
        #expect(attempt.state(for: env.card) == .waiting)
        #expect(attempt.state(for: otherCard) == .unavailable("작업 대상 변경됨"))
    }

    @Test func cardStatusChangesMoveTheResumeStatus() throws {
        let env = try Env()
        let attempt = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 1)
        try env.resume("new", .claude, project: env.app, cwd: "/work/app", at: t0 + 2)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .connected(.claude))
        // 사용자가 작업중 카드를 다음 할 일로 돌리면 연결이 풀린다.
        try CardLifecycle.move(env.card, to: .next, at: t0 + 3, in: env.context)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .disconnected(.claude))
        try CardLifecycle.move(env.card, to: .done, at: t0 + 4, in: env.context)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .unavailable("완료한 카드"))
        #expect(CardResumeStatus.of(env.card, attempt: nil) == .unavailable("완료한 카드"))
        try CardLifecycle.move(env.card, to: .archived, at: t0 + 5, in: env.context)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .unavailable("보관한 카드"))
        try CardLifecycle.move(env.card, to: .next, at: t0 + 6, in: env.context)
        #expect(CardResumeStatus.of(env.card, attempt: nil) == .ready)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .disconnected(.claude))
    }

    @Test func cardStartedByAnUnrelatedOldSessionStaysCopied() throws {
        let env = try Env()
        let old = makeSession(env.context, env.app, id: "old")
        CardLifecycle.attach(env.card, old, at: t0, in: env.context)
        let attempt = CardResumeAttempt(card: env.card, provider: .claude, at: t0 + 1)
        #expect(env.card.status == .active)
        #expect(CardResumeStatus.of(env.card, attempt: attempt) == .copied(.claude))
    }
}
