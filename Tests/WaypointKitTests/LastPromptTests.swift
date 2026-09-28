import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 마지막 요청 문장(`Session.lastPrompt`, SPEC 5장): 메인 세션의 `UserPromptSubmit` 사용자 문장.
@Suite struct LastPromptTests {

    /// 픽스처 본문의 필드를 바꿔 보낸다. 값이 `NSNull`이면 그 필드를 뺀다.
    @discardableResult
    func send(_ h: HookHarness, _ name: String = "doc-UserPromptSubmit", at date: Date, delivers: Bool = true,
              override: [String: Any] = [:]) throws -> String? {
        var object = try #require(try JSONSerialization.jsonObject(with: try fixture(name)) as? [String: Any])
        for (key, value) in override { object[key] = value is NSNull ? nil : value }
        let input = try #require(HookInput(event: nil, object: object))
        return h.processor.handle(input, at: date, delivers: delivers)
    }

    func input(_ fields: [String: Any]) throws -> HookInput {
        var object: [String: Any] = ["session_id": "s", "hook_event_name": "UserPromptSubmit"]
        for (key, value) in fields { object[key] = value }
        return try #require(HookInput(event: nil, object: object))
    }

    // MARK: - 뽑기 규칙 (`HookParsing.userPrompt`)

    @Test func realFixtures() throws {
        #expect(HookParsing.userPrompt(try fixtureInput("real-UserPromptSubmit")) == "hi 라고만 답해")
        #expect(HookParsing.userPrompt(try fixtureInput("doc-UserPromptSubmit")) == "LDG-14 이어서 하자")
        // 서브에이전트 완료 알림(`<agent-message from=…>`)은 사용자 문장이 아니다
        #expect(try fixtureInput("real-UserPromptSubmit-agent-message").prompt?.hasPrefix("<agent-message") == true)
        #expect(HookParsing.userPrompt(try fixtureInput("real-UserPromptSubmit-agent-message")) == nil)
    }

    @Test func bothFieldNames() throws {
        #expect(HookParsing.userPrompt(try input(["prompt": "가"])) == "가")
        #expect(HookParsing.userPrompt(try input(["prompt_text": "나"])) == "나")
        #expect(HookParsing.userPrompt(try input(["prompt": "", "prompt_text": "다"])) == "다")
        #expect(HookParsing.userPrompt(try input([:])) == nil)
    }

    @Test func trimsAndSkips() throws {
        #expect(HookParsing.userPrompt(try input(["prompt": "  \n 보드 타일 고쳐 줘\n\n "])) == "보드 타일 고쳐 줘")
        #expect(HookParsing.userPrompt(try input(["prompt": ""])) == nil)
        #expect(HookParsing.userPrompt(try input(["prompt": " \n\t "])) == nil)
        #expect(HookParsing.userPrompt(try input(["prompt": "<task-notification>\n<task-id>b1</task-id>"])) == nil)
        #expect(HookParsing.userPrompt(try input(["prompt": "\n<system-reminder>x</system-reminder>"])) == nil)
        // 슬래시 명령은 그대로
        #expect(HookParsing.userPrompt(try input(["prompt": "/tracker init"])) == "/tracker init")
        // 붙여 넣은 글은 태그만 벗긴다
        let pasted = "\n\n<pasted_content id=\"38ae\">\n[삭제] w1 큰 작업은 쪼갠다\n</pasted_content>\n"
        #expect(HookParsing.userPrompt(try input(["prompt": pasted])) == "[삭제] w1 큰 작업은 쪼갠다")
        #expect(HookParsing.userPrompt(try input(["prompt": "<pasted_content id=\"1\"></pasted_content>"])) == nil)
    }

    @Test func subagentHookIsIgnored() throws {
        #expect(HookParsing.userPrompt(try input(["prompt": "가", "agent_id": "a4d2c8f1e0b3a297"])) == nil)
    }

    @Test func keepsFirst300Characters() throws {
        let long = String(repeating: "가나다라마", count: 70)  // 350자
        let kept = try #require(HookParsing.userPrompt(try input(["prompt": long])))
        #expect(kept.count == 300)
        #expect(long.hasPrefix(kept))
        // 결합 문자·이모지도 문자 하나로 센다
        let emoji = String(repeating: "👩‍💻", count: 301)
        #expect(HookParsing.userPrompt(try input(["prompt": emoji]))?.count == 300)
        let exact = String(repeating: "a", count: 300)
        #expect(HookParsing.userPrompt(try input(["prompt": exact])) == exact)
    }

    // MARK: - 저장

    @Test func mainSessionStoresLatestPrompt() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0)
        #expect(try h.session()?.lastPrompt == nil)
        try send(h, at: t0 + 60)
        #expect(try h.session()?.lastPrompt == "LDG-14 이어서 하자")
        try send(h, at: t0 + 120, override: ["prompt": "  다음은 파서\n"])
        #expect(try h.session()?.lastPrompt == "다음은 파서")
        #expect(try h.session()?.lastSeenAt == t0 + 120)
    }

    /// 요청 시각(`lastPromptAt`)은 문장과 함께 적고, 문장을 두는 경우엔 시각도 둔다.
    @Test func promptTimeMovesWithPrompt() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0)
        #expect(try h.session()?.lastPromptAt == nil)
        try send(h, at: t0 + 60)
        #expect(try h.session()?.lastPromptAt == t0 + 60)
        // Stop·자동 메시지·빈 문장·서브에이전트 훅은 시각을 옮기지 않는다
        try send(h, "doc-Stop", at: t0 + 90)
        try send(h, "real-UserPromptSubmit-agent-message", at: t0 + 120,
                 override: ["session_id": HookHarness.sessionID, "cwd": "/Users/me/dev/ledger"])
        try send(h, at: t0 + 150, override: ["prompt": "   "])
        try send(h, at: t0 + 180, override: ["prompt": "서브에이전트 안", "agent_id": HookHarness.agentID])
        #expect(try h.session()?.lastPromptAt == t0 + 60)
        try send(h, at: t0 + 240, override: ["prompt": "다음"])
        #expect(try h.session()?.lastPromptAt == t0 + 240)
    }

    /// outbox로 늦게 온 옛 프롬프트는 시각도 덮지 않고, 빈 값은 채운다(문장과 같은 규칙).
    @Test func promptTimeFollowsOutboxOrderRule() throws {
        let h = try HookHarness()
        try send(h, at: t0 + 600, override: ["prompt": "지금 요청"])
        try send(h, at: t0 + 60, delivers: false, override: ["prompt": "옛 요청"])
        #expect(try h.session()?.lastPromptAt == t0 + 600)

        let empty = try HookHarness()
        try send(empty, "doc-Stop", at: t0 + 600)
        try send(empty, at: t0 + 60, delivers: false, override: ["prompt": "늦게 온 요청"])
        #expect(try empty.session()?.lastPromptAt == t0 + 60)
    }

    @Test func skippedPromptsKeepPreviousValue() throws {
        let h = try HookHarness()
        try send(h, at: t0)
        try send(h, "real-UserPromptSubmit-agent-message", at: t0 + 60,
                 override: ["session_id": HookHarness.sessionID, "cwd": "/Users/me/dev/ledger"])
        try send(h, at: t0 + 90, override: ["prompt": "   "])
        #expect(try h.session()?.lastPrompt == "LDG-14 이어서 하자")
        // 활동 시각은 그대로 옮긴다
        #expect(try h.session()?.lastSeenAt == t0 + 90)
    }

    @Test func subagentPromptDoesNotTouchMainSession() throws {
        let h = try HookHarness()
        try send(h, at: t0)
        try send(h, at: t0 + 60, override: ["prompt": "서브에이전트 안", "agent_id": HookHarness.agentID])
        #expect(try h.session()?.lastPrompt == "LDG-14 이어서 하자")
        #expect(try h.session(HookHarness.agentID) == nil)
    }

    @Test func promptTextFieldIsStored() throws {
        let h = try HookHarness()
        try send(h, at: t0, override: ["prompt": NSNull(), "prompt_text": "옛 이름 필드"])
        #expect(try h.session()?.lastPrompt == "옛 이름 필드")
    }

    /// outbox로 늦게 들어온 옛 프롬프트는 더 최근 값을 덮지 않는다.
    @Test func olderOutboxPromptDoesNotOverwriteNewer() throws {
        let h = try HookHarness()
        try send(h, at: t0 + 600, override: ["prompt": "지금 요청"])
        try send(h, at: t0 + 60, delivers: false, override: ["prompt": "앱이 꺼져 있던 동안의 요청"])
        #expect(try h.session()?.lastPrompt == "지금 요청")
        #expect(try h.session()?.lastSeenAt == t0 + 600)

        // Stop이 더 늦어도 같다(마지막 활동보다 옛 프롬프트)
        try send(h, "doc-Stop", at: t0 + 900)
        try send(h, at: t0 + 700, delivers: false, override: ["prompt": "그 사이 요청"])
        #expect(try h.session()?.lastPrompt == "지금 요청")
    }

    /// outbox로만 들어온 프롬프트도 저장한다(시각 순서대로 흡수하면 마지막 것이 남는다).
    @Test func outboxPromptsAreStoredInOrder() throws {
        let h = try HookHarness()
        try send(h, "doc-SessionStart", at: t0, delivers: false)
        try send(h, at: t0 + 60, delivers: false, override: ["prompt": "첫 요청"])
        try send(h, "doc-Stop", at: t0 + 120, delivers: false)
        try send(h, at: t0 + 180, delivers: false, override: ["prompt": "둘째 요청"])
        #expect(try h.session()?.lastPrompt == "둘째 요청")
    }

    /// 비어 있으면 옛 프롬프트라도 채운다.
    @Test func olderPromptFillsEmptyValue() throws {
        let h = try HookHarness()
        try send(h, "doc-Stop", at: t0 + 600)
        try send(h, at: t0 + 60, delivers: false, override: ["prompt": "늦게 온 요청"])
        #expect(try h.session()?.lastPrompt == "늦게 온 요청")
        #expect(try h.session()?.lastSeenAt == t0 + 600)
    }

    @Test func outboxLineIsStored() throws {
        let h = try HookHarness()
        let payload = String(decoding: try fixture("doc-UserPromptSubmit"), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "")
        let line = #"{"event":"UserPromptSubmit","receivedAt":\#(Int(t0.timeIntervalSince1970)),"payload":\#(payload)}"#
        let entry = try #require(Outbox.parse(line: Substring(line)))
        h.processor.handle(entry)
        #expect(try h.session()?.lastPrompt == "LDG-14 이어서 하자")
    }
}

/// 작업중 줄·타일 경과(`SessionFormat.rowElapsed`).
@Suite struct RowElapsedTests {
    let now = t0 + 5 * 3600

    func elapsed(_ state: CardWorkState, prompt: Date? = nil, attached: Date? = nil,
                 seen: Date? = nil) -> String? {
        SessionFormat.rowElapsed(state: state, lastPromptAt: prompt, attachedAt: attached,
                                 lastSeenAt: seen ?? now, now: now)
    }

    @Test func cardlessLiveCountsFromLastPrompt() {
        #expect(elapsed(.live, prompt: now - 12 * 60) == "12분")
        #expect(elapsed(.live, prompt: now - 20) == "방금")
        // 요청 시각이 없으면 비운다(세션 시작 시각으로 대신하지 않는다)
        #expect(elapsed(.live) == nil)
    }

    @Test func cardRowCountsFromAttachedAt() {
        #expect(elapsed(.live, prompt: now - 12 * 60, attached: now - 38 * 60) == "38분")
        #expect(elapsed(.live, attached: now - 3900) == "1시간 5분")
    }

    @Test func stalledCountsFromLastSeen() {
        #expect(elapsed(.stalled, prompt: now - 3600, seen: now - 22 * 60) == "멈춤 22분")
        #expect(elapsed(.stalled, seen: now - 22 * 60) == "멈춤 22분")
        #expect(elapsed(.stalled, attached: now - 3600, seen: now - 22 * 60) == "멈춤 22분")
    }

    @Test func noneIsEmpty() {
        #expect(elapsed(.none, prompt: now - 60, attached: now - 60) == nil)
    }
}

@Suite struct PromptPreviewTests {
    @Test func noPromptFallsBack() {
        #expect(SessionFormat.promptPreview(nil) == nil)
        #expect(SessionFormat.promptPreview("") == nil)
        #expect(SessionFormat.promptPreview(" \n\t ") == nil)
        #expect(SessionFormat.noCardTitle(prompt: nil) == ("카드 없음", false))
        #expect(SessionFormat.noCardTitle(prompt: "  ") == ("카드 없음", false))
    }

    @Test func collapsesWhitespaceToOneLine() {
        #expect(SessionFormat.promptPreview("보드 타일\n\n  고쳐 줘\t빨리") == "보드 타일 고쳐 줘 빨리")
        #expect(SessionFormat.noCardTitle(prompt: "/tracker init") == ("/tracker init", true))
    }

    @Test func cutsLongPrompt() throws {
        let exact = String(repeating: "가", count: SessionFormat.promptPreviewLimit)
        #expect(SessionFormat.promptPreview(exact) == exact)
        let long = String(repeating: "가", count: 300)
        let preview = try #require(SessionFormat.promptPreview(long))
        #expect(preview.count == SessionFormat.promptPreviewLimit + 1)
        #expect(preview.hasSuffix("…"))
        #expect(preview.hasPrefix(String(repeating: "가", count: SessionFormat.promptPreviewLimit)))
    }
}
