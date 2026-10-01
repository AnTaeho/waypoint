import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct ProjectAttributionTests {
    @Test func explicitBindingCreatesCodexSessionFromParentFolder() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx); p.rootPath = "/workspace/waypoint"
        let tools = MCPTools(context: ctx, now: { t0 })
        let result = try tools.call("session_bind", ["project": "LDG", "sessionId": "codex:real-id",
                                                     "provider": "codex", "cwd": "/workspace"])
        #expect(result["context"]?.stringValue?.contains("Waypoint: LDG") == true)
        #expect(result["sessionId"] == "codex:real-id")
        let s = try #require(ctx.fetch(FetchDescriptor<Session>()).first)
        #expect(s.cwd == "/workspace" && s.project === p && s.provider == .codex)
        let card = p.makeCard(in: ctx, title: "work", status: .next, at: t0)
        _ = try tools.call("card_start", ["id": .string(card.displayID), "sessionId": "codex:real-id"])
        #expect(card.status == .active)
    }

    @Test func switchingProjectsDetachesCardsButPreservesHistoricalEventsAndSubagents() throws {
        let (container, ctx) = try makeContext(); _ = container
        let a = makeProject(ctx)
        let b = makeProject(ctx, key: "TRK")
        let main = makeSession(ctx, a, id: "main")
        let child = makeSession(ctx, a, id: "sub", parent: main)
        let old = a.makeCard(in: ctx, title: "old", status: .idea, at: t0)
        CardLifecycle.attach(old, main, at: t0, in: ctx)
        let event = Event.record(.fileChanged, in: ctx, project: a, card: old, session: main, at: t0)
        let tools = MCPTools(context: ctx, now: { t0 + 60 })
        let result = try tools.call("session_bind", ["project": "TRK", "sessionId": "main",
                                                     "provider": "claude", "cwd": "/workspace"])
        #expect(result["detached"]?.arrayValue == [.string(old.displayID)])
        #expect(old.status == .idea && old.openCardSessions.isEmpty)
        #expect(event.project === a && event.card === old && child.project === a)
        #expect(main.project === b && main.contextProjectKey == "TRK")
        let card = b.makeCard(in: ctx, title: "new", status: .next, at: t0)
        _ = try tools.call("card_start", ["id": .string(card.displayID), "sessionId": "main"])
        #expect(card.status == .active)
    }

    @Test func rejectsArchivedTargetEndedSessionAndWrongProvider() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx)
        let s = makeSession(ctx, p, id: "main"); s.endedAt = t0
        let tools = MCPTools(context: ctx, now: { t0 })
        #expect(throws: MCPToolError.self) {
            try tools.call("session_bind", ["project": "LDG", "sessionId": "main", "provider": "claude", "cwd": "/workspace"])
        }
        #expect(throws: MCPToolError.self) {
            try tools.call("session_bind", ["project": "LDG", "sessionId": "raw-codex", "provider": "codex", "cwd": "/workspace"])
        }
        p.archivedAt = t0
        #expect(throws: MCPToolError.self) {
            try tools.call("session_bind", ["project": "LDG", "sessionId": "codex:new", "provider": "codex", "cwd": "/workspace"])
        }
    }

    func edit(_ path: String, id: String = "from-parent") throws -> HookInput {
        try #require(HookInput(event: "PostToolUse", object: ["session_id": id, "cwd": "/workspace",
            "tool_name": "Write", "tool_input": ["file_path": path, "content": "hello"]]))
    }

    @Test func changedFileCreatesSessionUnderActualProject() throws {
        let (container, ctx) = try makeContext(); _ = container
        let p = makeProject(ctx); p.rootPath = "/workspace/waypoint"
        let processor = HookProcessor(context: ctx)
        processor.handle(try edit("/workspace/waypoint/Sources/a.swift"), at: t0)
        let s = try #require(ctx.fetch(FetchDescriptor<Session>()).first)
        #expect(s.project === p && s.cwd == "/workspace")
        let events = try ctx.fetch(FetchDescriptor<Event>()).filter { $0.type == .fileChanged }
        #expect(events.count == 1 && events[0].project === p)
        #expect(events[0].payloadValues["path"]?.stringValue == "Sources/a.swift")
    }

    @Test func editsToOtherProjectDoNotContaminateAttachedCard() throws {
        let (container, ctx) = try makeContext(); _ = container
        let a = makeProject(ctx); a.rootPath = "/workspace/a"
        let b = makeProject(ctx, key: "TRK"); b.rootPath = "/workspace/b"
        let s = makeSession(ctx, a, id: "from-parent")
        let card = a.makeCard(in: ctx, title: "a", status: .next, at: t0)
        CardLifecycle.attach(card, s, at: t0, in: ctx)
        let processor = HookProcessor(context: ctx)
        processor.handle(try edit("/workspace/b/file.swift"), at: t0 + 1)
        processor.handle(try edit("/outside/file.swift"), at: t0 + 2)
        let changes = try ctx.fetch(FetchDescriptor<Event>()).filter { $0.type == .fileChanged }
        #expect(changes.count == 1 && changes[0].project === b && changes[0].card == nil)
        #expect(s.project === a && card.status == .active)
    }

    @Test func oneToolCanRecordTwoProjectsWithoutChoosingAnArbitraryDefault() throws {
        let (container, ctx) = try makeContext(); _ = container
        let a = makeProject(ctx); a.rootPath = "/workspace/a"
        let b = makeProject(ctx, key: "TRK"); b.rootPath = "/workspace/b"
        let input = try #require(HookInput(event: "PostToolUse", object: [
            "session_id": "multi", "cwd": "/workspace", "tool_name": "Bash",
            "tool_input": ["command": "edit"],
            "tool_response": ["bashEditDiff": ["changedFiles": ["/workspace/a/a.swift", "/workspace/b/b.swift"]]]]))
        HookProcessor(context: ctx).handle(input, at: t0)
        let changes = try ctx.fetch(FetchDescriptor<Event>()).filter { $0.type == .fileChanged }
        #expect(changes.count == 2 && Set(changes.compactMap { $0.project?.key }) == ["LDG", "TRK"])
        #expect(try ctx.fetch(FetchDescriptor<Session>()).first?.project == nil)
    }

    @Test func parallelSubagentKeepsItsProjectAfterMainSwitches() throws {
        let (container, ctx) = try makeContext(); _ = container
        let a = makeProject(ctx); a.rootPath = "/workspace/a"
        let b = makeProject(ctx, key: "TRK"); b.rootPath = "/workspace/b"
        let main = makeSession(ctx, a, id: "main")
        let sub = makeSession(ctx, a, id: "sub", parent: main)
        let card = a.makeCard(in: ctx, title: "child", status: .next, at: t0)
        CardLifecycle.attach(card, sub, at: t0, in: ctx)
        SessionProjectBinding.bind(main, to: b, at: t0 + 1, in: ctx)
        let input = try #require(HookInput(event: "PostToolUse", object: ["session_id": "main", "agent_id": "sub",
            "cwd": "/workspace", "tool_name": "Write", "tool_input": ["file_path": "/workspace/a/test.swift", "content": "x"]]))
        HookProcessor(context: ctx).handle(input, at: t0 + 2)
        let changes = try ctx.fetch(FetchDescriptor<Event>()).filter { $0.type == .fileChanged }
        #expect(changes.count == 1 && changes[0].project === a && changes[0].card === card)
    }
}
