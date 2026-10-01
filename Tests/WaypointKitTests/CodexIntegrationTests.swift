import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// doc-codex 픽스처는 공식 훅 문서 기반이다. 실제 실행 픽스처와 구분한다.
@Suite struct CodexIntegrationTests {
    @discardableResult
    func send(_ name: String, to h: HookHarness, at date: Date, pid: Int? = nil, delivers: Bool = true) throws -> String? {
        h.processor.handle(event: nil, json: try fixture("doc-codex-\(name)"), at: date,
                           delivers: delivers, provider: .codex, processPid: pid)
    }

    @Test func overlappingIDsRemainSeparateAndPersistProvider() throws {
        let h = try HookHarness()
        let data = try fixture("doc-codex-SessionStart")
        h.processor.handle(event: nil, json: data, at: t0) // 같은 원본 ID의 Claude
        let text = try #require(try send("SessionStart", to: h, at: t0, pid: 9876))
        let claude = try #require(try h.session("same-id"))
        let codex = try #require(try h.session("codex:same-id"))
        #expect(claude.provider == .claude)
        #expect(codex.provider == .codex)
        #expect(codex.processPid == 9876)
        #expect(codex.claudePid == nil)
        #expect(text.contains("sessionId: codex:same-id\nprovider: codex"))
        #expect(text.contains("waypoint-tracker"))
        let fresh = ModelContext(h.container)
        let id = codex.id
        let stored = try #require(try fresh.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first)
        #expect(stored.provider == .codex)
        #expect(DashboardQuery.rows(for: h.project, now: t0).count == 2)
        #expect(SessionFormat.label(for: codex) == "Codex · sess·same")
        #expect(CardFormat.originName(.codex) == "Codex")
    }

    @Test func codexRouteUsesGenericPidAndKeepsRawPayload() throws {
        let payload = try fixture("doc-codex-SessionStart")
        let request = HTTPRequest(method: "POST", path: "/hooks/codex/SessionStart",
                                  headers: ["x-waypoint-process-pid": "9876", "x-waypoint-claude-pid": "7777"], body: payload)
        var called = false
        let response = HookRouter.respond(to: request) { provider, event, body, pid in
            called = true
            #expect(provider == .codex)
            #expect(event == "SessionStart")
            #expect(body == payload)
            #expect(pid == 9876)
            return "Waypoint"
        }
        #expect(called)
        #expect(response == .text("Waypoint"))
        #expect(HookRouter.eventName(from: "/hooks/codex/../Stop") == nil)
        #expect(HookRouter.eventName(from: "/hooks/codex/") == nil)
    }

    @Test func promptLateContextAndPidAreMonotonic() throws {
        let h = try HookHarness()
        try send("SessionStart", to: h, at: t0, pid: 9000, delivers: false)
        let session = try #require(try h.session("codex:same-id"))
        #expect(session.contextProjectKey == nil)
        let first = try send("UserPromptSubmit", to: h, at: t0 + 60, pid: 9999)
        #expect(first?.contains("sessionId: codex:same-id") == true)
        #expect(session.lastPrompt == "LDG-1 파일 변경 기록을 구현해줘")
        #expect(session.contextProjectKey == "LDG")
        #expect(try send("UserPromptSubmit", to: h, at: t0 + 90) == nil)
        try send("Stop", to: h, at: t0 + 30, pid: 9000)
        #expect(session.processPid == 9999)
        #expect(session.lastSeenAt == t0 + 90)
        try send("Interrupt", to: h, at: t0 + 120)
        #expect(session.endedAt == nil)
        #expect(session.lastSeenAt == t0 + 120)
    }

    @Test func sharedMcpCreatesStartsAndHandsOffCodexCards() throws {
        let h = try HookHarness()
        try send("SessionStart", to: h, at: t0)
        let tools = MCPTools(context: h.context, home: "/Users/me", now: { t0 + 60 })
        let value = try tools.call("card_create", ["project": "LDG", "title": "Codex 작업", "sessionId": "codex:same-id"])
        let id = try #require(value["id"]?.stringValue)
        let card = try #require(h.card(1))
        #expect(card.origin == .codex)
        #expect(card.originSessionId == "codex:same-id")
        let result = try tools.call("card_start", ["id": .string(id), "sessionId": "codex:same-id"])
        #expect(result["card"]?["sessions"]?.arrayValue?.first?["provider"] == "codex")
        #expect(card.status == .active)
        _ = try tools.call("card_handoff", ["id": .string(id), "nextSessionNote": "파일 파서 완료. 다음은 테스트"])
        try h.context.save()
        try send("SessionEnd", to: h, at: t0 + 120)
        #expect(card.status == .next)
        #expect(card.openCardSessions.isEmpty)
        let text = try #require(try h.send("doc-SessionStart", at: t0 + 180))
        #expect(text.contains("파일 파서 완료. 다음은 테스트")) // Claude에서도 이어 받는다
        _ = try tools.call("card_start", ["id": .string(id), "sessionId": .string(HookHarness.sessionID)])
        #expect(card.status == .active)
        #expect(card.openCardSessions.first?.session?.provider == .claude)
    }

    @Test func explicitProviderWorksWithoutSessionAndRejectsUnknown() throws {
        let h = try MCPHarness()
        let value = try h.ok("card_create", ["project": "PRB", "title": "아이디어", "provider": "codex", "kind": "idea"])
        #expect(value["status"] == "idea")
        #expect(h.card(1)?.origin == .codex)
        #expect(try h.fails("card_create", ["project": "PRB", "title": "실패", "provider": "unknown"]).contains("provider"))
        #expect(h.project.cards?.count == 1)
    }

    @Test func subagentLifecycleAndPatchUseCodexIdentity() throws {
        let h = try HookHarness()
        let parentCard = h.project.makeCard(in: h.context, title: "메인", status: .next, at: t0)
        let childCard = h.project.makeCard(in: h.context, title: "하위", status: .next, parent: parentCard, at: t0)
        try h.context.save()
        try send("SessionStart", to: h, at: t0)
        let parent = try #require(try h.session("codex:same-id"))
        CardLifecycle.attach(parentCard, parent, at: t0, in: h.context)
        try send("PreToolUse-Agent", to: h, at: t0 + 10)
        try send("SubagentStart", to: h, at: t0 + 20)
        let child = try #require(try h.session("codex:agent-1"))
        #expect(child.parent === parent)
        #expect(child.provider == .codex)
        #expect(childCard.status == .active)
        var object = try #require(try JSONSerialization.jsonObject(with: fixture("doc-codex-PostToolUse-apply_patch")) as? [String: Any])
        object["agent_id"] = "agent-1"
        let data = try JSONSerialization.data(withJSONObject: object)
        h.processor.handle(event: nil, json: data, at: t0 + 30, provider: .codex)
        #expect(events(childCard, .fileChanged).count == 2)
        #expect(events(parentCard, .fileChanged).isEmpty)
        #expect(events(childCard, .fileChanged).allSatisfy { $0.session === child })
        try send("SubagentStop", to: h, at: t0 + 40)
        #expect(child.endedAt == t0 + 40)
        #expect(childCard.status == .next)
        #expect(parent.endedAt == nil)
        try send("SessionEnd", to: h, at: t0 + 50)
        #expect(parentCard.status == .next)
    }

    @Test func patchesNormalizeStringsCountLinesAndIgnoreFailures() throws {
        let data = try fixture("doc-codex-PostToolUse-apply_patch")
        let input = try #require(HookInput(event: nil, json: data, provider: .codex))
        let files = HookParsing.changedFiles(input)
        #expect(files.map(\.path) == ["/Users/me/dev/ledger/new.swift", "/Users/me/dev/ledger/old.swift"])
        #expect(files.map(\.added) == [2, 1])
        #expect(files.map(\.removed) == [0, 1])
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["tool_input"] = String(decoding: try JSONSerialization.data(withJSONObject: input.toolInput), as: UTF8.self)
        object["tool_response"] = "Failed to find expected lines"
        let failed = try #require(HookInput(event: nil, object: object, provider: .codex))
        #expect(HookParsing.changedFiles(failed).isEmpty)
        object["tool_response"] = ["output": "Success. Updated the following files:\nA new.swift\nM old.swift", "metadata": ["exit_code": 1]]
        #expect(HookParsing.changedFiles(try #require(HookInput(event: nil, object: object, provider: .codex))).isEmpty)
    }

    @Test func rawPatchRenameAndDeleteAreRecorded() throws {
        let object: [String: Any] = [
            "session_id": "s", "cwd": "/tmp/project", "hook_event_name": "PostToolUse", "tool_name": "apply_patch",
            "tool_input": "*** Begin Patch\n*** Update File: before.swift\n*** Move to: after.swift\n@@\n-old\n+new\n*** Delete File: gone.swift\n*** End Patch",
            "tool_response": "Success. Updated the following files:\nM after.swift\nD gone.swift\n",
        ]
        let files = HookParsing.changedFiles(try #require(HookInput(event: nil, object: object, provider: .codex)))
        #expect(files.map(\.path) == ["/tmp/project/after.swift", "/tmp/project/gone.swift"])
        #expect(files[0].added == 1 && files[0].removed == 1)
    }

    @Test func bashCommitsUseTextResponse() throws {
        let h = try HookHarness()
        try send("SessionStart", to: h, at: t0)
        try send("PostToolUse-Bash-commit", to: h, at: t0 + 30)
        let session = try #require(try h.session("codex:same-id"))
        let commit = try #require(session.events?.first { $0.type == .commit })
        #expect(commit.payloadValues["hash"]?.stringValue == "abc1234")
        #expect(commit.payloadValues["message"]?.stringValue == "Codex 연결")
        #expect(session.gitBranch == "feat/codex")
    }

    @Test func outboxKeepsProviderAndReplaysWithoutInjection() throws {
        let h = try HookHarness()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-codex-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = try JSONSerialization.jsonObject(with: fixture("doc-codex-SessionStart"))
        let object: [String: Any] = ["provider": "codex", "event": "SessionStart", "receivedAt": t0.timeIntervalSince1970,
                                   "processPid": 9000, "payload": payload]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        try (line + "\n").write(to: directory.appendingPathComponent(Outbox.fileName), atomically: true, encoding: .utf8)
        let result = Outbox.drain(directory: directory) { h.processor.handle($0) }
        #expect(result.processed == 1)
        let session = try #require(try h.session("codex:same-id"))
        #expect(session.provider == .codex)
        #expect(session.processPid == 9000)
        #expect(session.contextProjectKey == nil)
        #expect(h.processor.sweep(now: t0 + 60, probe: { _ in nil }) == 1)
        #expect(session.endedAt == t0 + 60)
    }

    @Test func projectInitRetainsCodexOriginForSeedCards() throws {
        let (container, context) = try makeContext()
        _ = container
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-codex-init-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = ProjectDraftQueue()
        let tools = MCPTools(context: context, drafts: queue, now: { t0 })
        _ = try tools.call("project_init", ["cwd": .string(root.path), "name": "Codex", "key": "CDX", "provider": "codex",
                                            "seedCards": [["title": "초기 작업"]]])
        let draft = try #require(queue.current)
        #expect(draft.provider == .codex)
        let project = try ProjectRegistry.register(draft, at: t0, context: context)
        #expect(project.cards?.first?.origin == .codex)
    }
}
