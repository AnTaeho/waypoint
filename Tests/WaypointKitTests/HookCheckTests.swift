import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 훅 입력 → 검증 근거.
@Suite struct HookCheckTests {
    static let cwd = "/Users/me/dev/ledger"

    static func bash(_ command: String, event: String = "PostToolUse", toolUseID: String = "toolu_1",
                     response: [String: Any]? = ["stdout": "", "stderr": "", "interrupted": false],
                     error: String? = nil, agentID: String? = nil, background: Bool = false) throws -> Data {
        var object: [String: Any] = ["session_id": HookHarness.sessionID, "cwd": cwd, "hook_event_name": event,
                                     "tool_name": "Bash", "tool_use_id": toolUseID,
                                     "tool_input": ["command": command, "run_in_background": background]]
        if let response { object["tool_response"] = response }
        if let error { object["error"] = error; object["is_interrupt"] = false }
        if let agentID { object["agent_id"] = agentID; object["agent_type"] = "general-purpose" }
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func parsed(_ data: Data) throws -> HookInput {
        try #require(HookInput(event: nil, json: data))
    }

    static func input(_ object: [String: Any]) throws -> HookInput {
        try #require(HookInput(event: nil, object: object))
    }

    static func object(_ name: String) throws -> [String: Any] {
        let data = try fixture(name)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 실측(2.1.286): 비영 종료는 PostToolUseFailure `error: "Exit code 3"`, 성공은 PostToolUse(종료 코드 없음).
    @Test func realFailureAndBackgroundFixtures() throws {
        var failure = try Self.object("real-PostToolUseFailure-Bash")
        #expect(HookParsing.check(try Self.input(failure)) == nil) // bash -c는 검증 명령 아님
        failure["tool_input"] = ["command": "bash test-fail.sh"]
        let failed = try #require(HookParsing.check(try Self.input(failure)))
        #expect(failed.outcome == .fail && failed.exitCode == 3)

        var background = try Self.object("real-PostToolUse-Bash-background")
        background["tool_input"] = ["command": "swift test", "run_in_background": true]
        #expect(HookParsing.check(try Self.input(background))?.outcome == .unknown)
        background["tool_input"] = ["command": "swift test"] // backgroundTaskId만으로도
        #expect(HookParsing.check(try Self.input(background))?.outcome == .unknown)

        var success = try Self.object("real-PostToolUse-Bash")
        #expect(HookParsing.check(try Self.input(success)) == nil) // ping
        success["tool_input"] = ["command": "bash test-pass.sh"]
        #expect(HookParsing.check(try Self.input(success))?.outcome == .pass)
    }

    /// 실측(2.1.286, Dev PRB-6): 검증 명령으로 판정된 성공·실패 실행.
    @Test func realTestRunFixtures() throws {
        let pass = try Self.input(try Self.object("real-PostToolUse-Bash-test"))
        #expect(HookParsing.check(pass)?.command == "bash test-pass.sh")
        #expect(HookParsing.check(pass)?.outcome == .pass)
        let fail = try Self.input(try Self.object("real-PostToolUseFailure-Bash-test"))
        #expect(fail.error == "Exit code 3\n1 test failed")
        #expect(HookParsing.check(fail)?.outcome == .fail)
        #expect(HookParsing.check(fail)?.exitCode == 3)
    }

    @Test func interruptedAndUnknownFailuresAreUnknown() throws {
        let interrupted = try Self.parsed(try Self.bash(
            "swift test", response: ["stdout": "", "interrupted": true]))
        #expect(HookParsing.check(interrupted)?.outcome == .unknown)
        let noCode = try Self.parsed(try Self.bash(
            "swift test", event: "PostToolUseFailure", response: nil, error: "Command timed out after 2m 0s"))
        #expect(HookParsing.check(noCode)?.outcome == .unknown)
    }

    @Test func codexExitCodes() throws {
        let failData = try fixture("doc-codex-PostToolUse-Bash-test-fail")
        let fail = try #require(HookInput(event: nil, json: failData, provider: .codex))
        #expect(HookParsing.check(fail)?.outcome == .fail)
        #expect(HookParsing.check(fail)?.exitCode == 1)
        let passData = try fixture("doc-codex-PostToolUse-Bash-test-pass")
        let pass = try #require(HookInput(event: nil, json: passData, provider: .codex))
        #expect(HookParsing.check(pass)?.outcome == .pass)
        #expect(HookParsing.check(pass)?.command == "cd /Users/me/dev/ledger && swift test")
        let array = try #require(HookInput(event: "PostToolUse", object: [
            "session_id": "x", "cwd": "/x", "tool_name": "Bash",
            "tool_input": ["command": ["bash", "-lc", "go test ./..."]], "tool_response": ["exit_code": 2],
        ], provider: .codex))
        #expect(HookParsing.check(array)?.outcome == .fail)
        let missing = try #require(HookInput(event: "PostToolUse", object: [
            "session_id": "x", "cwd": "/x", "tool_name": "Bash", "tool_input": ["command": "go test"], "tool_response": "ok",
        ], provider: .codex))
        #expect(HookParsing.check(missing)?.outcome == .unknown)
    }

    func started(_ h: HookHarness, criteria: [Criterion] = []) throws -> (Card, Session) {
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, criteria: criteria, at: t0)
        try h.send("doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        CardLifecycle.attach(card, main, at: t0, in: h.context)
        return (card, main)
    }

    @Test func recordsOnWorkingCardsOnce() throws {
        let h = try HookHarness()
        let (card, main) = try started(h)
        h.processor.handle(event: nil, json: try Self.bash("swift test"), at: t0 + 10)
        h.processor.handle(event: nil, json: try Self.bash("swift test"), at: t0 + 11) // 같은 tool_use_id 재수신
        h.processor.handle(event: nil, json: try Self.bash("swift test", event: "PostToolUseFailure", toolUseID: "toolu_2",
                                                           response: nil, error: "Exit code 1\n실패"), at: t0 + 20)
        // 실패 훅도 활동으로 센다
        #expect(main.lastSeenAt == t0 + 20)
        h.processor.handle(event: nil, json: try Self.bash("ls", toolUseID: "toolu_3"), at: t0 + 30)
        let records = CardEvidence.records(for: card)
        #expect(records.map(\.outcome) == [.fail, .pass])
        #expect(records.allSatisfy { $0.source == .hook && $0.provider == .claude && $0.criterion == nil })
        #expect(records.first?.exitCode == 1)
        #expect((card.events ?? []).first { $0.type == .check }?.session === main)
    }

    @Test func subagentWithoutCardUsesParentCardAndNoCardRecordsNothing() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        h.processor.handle(event: nil, json: try Self.bash("swift test"), at: t0 + 5)
        #expect(try h.context.fetchCount(FetchDescriptor<Event>(predicate: #Predicate { $0.typeRaw == "check" })) == 0)

        let card = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        let main = try #require(try h.session())
        CardLifecycle.attach(card, main, at: t0 + 6, in: h.context)
        try h.send("doc-SubagentStart", at: t0 + 7)
        h.processor.handle(event: nil, json: try Self.bash("pytest", toolUseID: "toolu_s", agentID: HookHarness.agentID), at: t0 + 8)
        let record = try #require(CardEvidence.records(for: card).first)
        #expect(record.command == "pytest" && record.outcome == .pass)
    }

    @Test func codexSessionRecordsWithProvider() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        h.processor.handle(event: nil, json: try fixture("doc-codex-SessionStart"), at: t0, provider: .codex)
        let codex = try #require(try h.session("codex:same-id"))
        CardLifecycle.attach(card, codex, at: t0, in: h.context)
        h.processor.handle(event: nil, json: try fixture("doc-codex-PostToolUse-Bash-test-fail"), at: t0 + 5, provider: .codex)
        h.processor.handle(event: nil, json: try fixture("doc-codex-PostToolUse-Bash-test-pass"), at: t0 + 9, provider: .codex)
        let records = CardEvidence.records(for: card)
        #expect(records.map(\.outcome) == [.pass, .fail])
        #expect(records.allSatisfy { $0.provider == .codex })
    }

    /// 재개: 끝난 세션이 같은 ID로 다시 살아나 카드를 잡으면 그 뒤 실행도 기록되고, 앞 근거는 그대로 남는다.
    @Test func resumedSessionKeepsAndAddsEvidence() throws {
        let h = try HookHarness()
        let (card, _) = try started(h)
        h.processor.handle(event: nil, json: try Self.bash("swift test"), at: t0 + 10)
        try h.send("doc-SessionEnd", at: t0 + 20)
        #expect(card.openCardSessions.isEmpty)
        h.processor.handle(event: "SessionStart", object: [
            "session_id": HookHarness.sessionID, "cwd": Self.cwd, "source": "resume",
        ], at: t0 + 100)
        let resumed = try #require(try h.session())
        #expect(resumed.endedAt == nil)
        CardLifecycle.attach(card, resumed, at: t0 + 101, in: h.context)
        h.processor.handle(event: nil, json: try Self.bash("swift test", event: "PostToolUseFailure", toolUseID: "toolu_r",
                                                           response: nil, error: "Exit code 1"), at: t0 + 110)
        #expect(CardEvidence.records(for: card).map(\.outcome) == [.fail, .pass])
    }
}

extension HookProcessor {
    /// 테스트용: JSON 객체를 바로 처리한다.
    @discardableResult
    func handle(event: String?, object: [String: Any], at date: Date) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return handle(event: event, json: data, at: date)
    }
}
