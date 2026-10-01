import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 늦은 주입(SPEC 5장): `Waypoint:` 블록을 받지 못한 메인 세션의 다음 `UserPromptSubmit`에 한 번.
@Suite struct LateContextTests {

    /// 픽스처 본문의 필드를 바꿔 보낸다(`cwd`를 옮기거나 `agent_id`를 붙일 때).
    @discardableResult
    func send(_ h: HookHarness, _ name: String, at date: Date, delivers: Bool = true,
              override: [String: Any] = [:]) throws -> String? {
        var object = try #require(try JSONSerialization.jsonObject(with: try fixture(name)) as? [String: Any])
        for (key, value) in override { object[key] = value }
        let input = try #require(HookInput(event: nil, object: object))
        return h.processor.handle(input, at: date, delivers: delivers)
    }

    let elsewhere = "/Users/me/workspace"

    /// 등록 전에 시작한 세션: 첫 UserPromptSubmit에 블록, 두 번째엔 없음.
    @Test func sessionStartedBeforeRegistrationGetsBlockOnce() throws {
        let h = try HookHarness()
        h.project.rootPath = "~/dev/not-yet"
        let start = try send(h, "doc-SessionStart", at: t0)
        #expect(start?.hasPrefix(SessionContext.unregistered) == true)
        #expect(try h.session() == nil)

        h.project.rootPath = "~/dev/ledger"  // 이제 등록됨
        let first = try #require(try send(h, "doc-UserPromptSubmit", at: t0 + 60))
        #expect(first.hasPrefix("Waypoint: LDG (가계부 앱)\nsessionId: \(HookHarness.sessionID)"))
        #expect(first.hasSuffix(SessionContext.skillHint))
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == "LDG")
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 120) == nil)
    }

    /// 다른(미등록) 폴더에서 시작해 등록 폴더로 옮겨 온 세션.
    @Test func sessionMovedInFromUnregisteredFolderGetsBlockOnce() throws {
        let h = try HookHarness()
        #expect((try send(h, "doc-SessionStart", at: t0, override: ["cwd": elsewhere]))?.hasPrefix(SessionContext.unregistered) == true)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 30, override: ["cwd": elsewhere]) == nil)
        #expect(try h.session() == nil)
        let text = try send(h, "doc-UserPromptSubmit", at: t0 + 60)
        #expect(text?.hasPrefix("Waypoint: LDG") == true)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 90) == nil)
    }

    /// PostToolUse가 먼저 세션을 만들어도(턴 중간에 등록) 다음 UserPromptSubmit에 준다.
    @Test func sessionCreatedByOtherHookGetsBlockOnNextPrompt() throws {
        let h = try HookHarness()
        #expect(try send(h, "doc-PostToolUse-Edit", at: t0) == nil)
        #expect(try h.session()?.contextProjectKey == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60)?.hasPrefix("Waypoint: LDG") == true)
    }

    /// SessionStart로 블록을 받은 세션은 더 받지 않는다.
    @Test func sessionThatGotSessionStartBlockGetsNothing() throws {
        let h = try HookHarness()
        let start = try #require(try send(h, "doc-SessionStart", at: t0))
        #expect(start.hasPrefix("Waypoint: LDG"))
        #expect(try h.session()?.contextProjectKey == "LDG")
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60) == nil)
    }

    /// 블록을 받은 프로젝트와 지금 프로젝트가 다르면 한 번 더.
    @Test func projectChangeGetsBlockAgainOnce() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-SessionStart", at: t0)
        let s = try #require(try h.session())
        let other = Project(key: "OCR", name: "영수증 인식", rootPath: "~/dev/ocr", createdAt: t0)
        h.context.insert(other)
        s.project = other
        try h.context.save()
        let text = try #require(try send(h, "doc-UserPromptSubmit", at: t0 + 60))
        #expect(text.hasPrefix("Waypoint: OCR (영수증 인식)"))
        #expect(s.contextProjectKey == "OCR")
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 90) == nil)
    }

    /// 미등록 폴더: 아무것도 주지 않는다(미등록 안내는 SessionStart에서만).
    @Test func unregisteredFolderGetsNothing() throws {
        let h = try HookHarness()
        #expect(try send(h, "doc-UserPromptSubmit", at: t0, override: ["cwd": elsewhere]) == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60, override: ["cwd": elsewhere]) == nil)
    }

    /// 보관된 프로젝트 폴더: 새 세션이든 보관 전에 시작한 세션이든 없음.
    @Test func archivedFolderGetsNothing() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-PostToolUse-Edit", at: t0)  // 블록 없이 만들어진 세션
        h.project.archivedAt = t0 + 30
        try h.context.save()
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60) == nil)
        #expect(try h.session()?.contextProjectKey == nil)
    }

    /// 서브에이전트 안에서 난 훅에는 주지 않는다.
    @Test func subagentHookGetsNothing() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-PostToolUse-Edit", at: t0)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60, override: ["agent_id": HookHarness.agentID]) == nil)
        #expect(try h.session()?.contextProjectKey == nil)
        // 메인 스레드의 다음 프롬프트에는 준다
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 90)?.hasPrefix("Waypoint: LDG") == true)
    }

    /// 끝난 세션의 늦은 기록(끝난 시각 이전)에는 주지 않는다.
    @Test func endedSessionGetsNothing() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-PostToolUse-Edit", at: t0)
        _ = try send(h, "doc-SessionEnd", at: t0 + 60)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 30) == nil)
    }

    /// outbox 흡수(이미 지난 훅): 출력도 없고 블록을 줬다고 적지도 않는다. 다음 실제 프롬프트에 준다.
    @Test func outboxPathDeliversNothingAndRecordsNothing() throws {
        let h = try HookHarness()
        #expect(try send(h, "doc-SessionStart", at: t0, delivers: false) == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 30, delivers: false) == nil)
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60)?.hasPrefix("Waypoint: LDG") == true)
    }

    /// `Outbox.Entry` 경로 그대로.
    @Test func outboxEntryDoesNotDeliver() throws {
        let h = try HookHarness()
        for (event, name, offset) in [("SessionStart", "doc-SessionStart", 0.0), ("UserPromptSubmit", "doc-UserPromptSubmit", 30)] {
            h.processor.handle(Outbox.Entry(provider: .claude, event: event, receivedAt: t0 + offset,
                                           payload: try fixture(name), claudePid: nil, processPid: nil))
        }
        #expect(try h.session()?.contextProjectKey == nil)
    }
}
