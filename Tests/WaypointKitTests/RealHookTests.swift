import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// `real-*.json`: Claude Code 2.1.283에서 로깅 모드로 받은 실제 훅 입력(2026-09-28, `~/workspace/waypoint-probe`).
@Suite struct RealHookTests {
    static let root = "/Users/antaeho/workspace/waypoint-probe"
    static let mainID = "b37a2306-ff96-4bbb-8096-ff578ddb977e"
    static let agentID = "ad5a8ca20b7faa5f7"

    @Test func realFixturesDecode() throws {
        let names = [
            "real-SessionStart", "real-SessionStart-resume", "real-SessionStart-fork",
            "real-UserPromptSubmit", "real-UserPromptSubmit-agent-message",
            "real-PreToolUse-Agent", "real-PreToolUse-Agent-background", "real-SubagentStart",
            "real-PostToolUse-Write-subagent", "real-SubagentStop", "real-SubagentStop-internal",
            "real-PostToolUse-Write", "real-PostToolUse-Edit", "real-PostToolUse-Bash-commit", "real-PostToolUse-Bash",
            "real-Stop", "real-SessionEnd",
        ]
        for name in names {
            let input = try fixtureInput(name)
            #expect(!input.sessionID.isEmpty, "\(name)")
            #expect(!input.cwd.isEmpty, "\(name)")
        }
        #expect(try fixtureInput("real-SessionStart").source == "startup")
        #expect(try fixtureInput("real-SessionStart-resume").source == "resume")
        #expect(try fixtureInput("real-SessionStart-fork").source == "fork")
        #expect(try fixtureInput("real-SessionEnd").reason == "other")
        #expect(try fixtureInput("real-PreToolUse-Agent").toolName == "Agent")
        // 서브에이전트 안의 훅: session_id는 부모와 같고 agent_id로 구분
        let start = try fixtureInput("real-SubagentStart")
        let write = try fixtureInput("real-PostToolUse-Write-subagent")
        #expect(start.sessionID == Self.mainID && start.agentID == Self.agentID)
        #expect(write.sessionID == Self.mainID && write.agentID == Self.agentID)
        #expect(start.agentType == "general-purpose")
        // 앱 내부 에이전트: agent_type 빈 값
        #expect(try fixtureInput("real-SubagentStop-internal").agentType == "")
    }

    @Test func editCountsFromStructuredPatch() throws {
        // b → B1, B2 : 실제 diff는 +2 −1
        let files = HookParsing.changedFiles(try fixtureInput("real-PostToolUse-Edit"))
        #expect(files.map(\.path) == ["\(Self.root)/notes.txt"])
        #expect(files.first?.added == 2)
        #expect(files.first?.removed == 1)

        // replace_all: 입력만으로는 한 번 바꾼 것으로 세지만 diff 조각은 전부 센다
        let replaceAll = HookInput(event: "PostToolUse", object: [
            "session_id": "s", "cwd": "/x", "tool_name": "Edit",
            "tool_input": ["file_path": "/x/f", "old_string": "a", "new_string": "b", "replace_all": true],
            "tool_response": ["structuredPatch": [
                ["lines": ["-a", "+b", " c"]], ["lines": ["-a", "+b"]],
            ]],
        ])!
        let counted = HookParsing.changedFiles(replaceAll)
        #expect(counted.first?.added == 2)
        #expect(counted.first?.removed == 2)
    }

    @Test func writeCreateHasEmptyPatchAndFallsBackToContent() throws {
        let files = HookParsing.changedFiles(try fixtureInput("real-PostToolUse-Write"))
        #expect(files.first?.added == 3)
        #expect(files.first?.removed == 0)
        // 덮어쓰기(update)는 diff 조각을 쓴다
        let update = HookInput(event: "PostToolUse", object: [
            "session_id": "s", "cwd": "/x", "tool_name": "Write",
            "tool_input": ["file_path": "/x/f", "content": "a\nz\n"],
            "tool_response": ["type": "update", "structuredPatch": [["lines": [" a", "-b", "-c", "+z"]]]],
        ])!
        let updated = HookParsing.changedFiles(update)
        #expect(updated.first?.added == 1)
        #expect(updated.first?.removed == 2)
    }

    @Test func bashCommitUsesGitOperationAndEditDiff() throws {
        let input = try fixtureInput("real-PostToolUse-Bash-commit")
        let files = HookParsing.changedFiles(input)
        #expect(files.map(\.path) == ["\(Self.root)/hello.txt"])
        #expect(files.first?.added == 1)
        let commit = try #require(HookParsing.commit(input))
        #expect(commit.hash == "c5a688e")
        #expect(commit.branch == "master")
        #expect(commit.message == "probe")

        // gitOperation만 있고 출력 줄이 없으면 메시지는 빈 문자열
        let quiet = HookInput(event: "PostToolUse", object: [
            "session_id": "s", "cwd": "/x", "tool_name": "Bash",
            "tool_input": ["command": "git commit -q -m x"],
            "tool_response": ["stdout": "", "gitOperation": ["commit": ["sha": "abc1234", "kind": "committed", "branch": "main"]]],
        ])!
        let q = try #require(HookParsing.commit(quiet))
        #expect(q.hash == "abc1234" && q.branch == "main" && q.message == "")
    }

    @Test func plainBashHasNoFilesOrCommit() throws {
        let input = try fixtureInput("real-PostToolUse-Bash")
        #expect(HookParsing.changedFiles(input).isEmpty)
        #expect(HookParsing.commit(input) == nil)
    }

    @Test func realSubagentFlowAttachesAndReturnsCard() throws {
        let (_, context) = try makeContext()
        let project = Project(key: "PRB", name: "훅 실측", rootPath: Self.root, createdAt: t0)
        context.insert(project)
        let card = project.makeCard(in: context, title: "실측용 카드", status: .next, at: t0)
        try context.save()
        let processor = HookProcessor(context: context, home: "/Users/antaeho", gitBranch: { _ in "master" })
        func send(_ name: String, at date: Date) throws {
            processor.handle(event: nil, json: try fixture(name), at: date)
        }
        func session(_ id: String) throws -> Session? {
            try context.fetch(FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id })).first
        }

        // 실측 순서: PreToolUse(Agent) → SubagentStart → PostToolUse(서브) → SubagentStop → UserPromptSubmit(<agent-message>)
        try send("real-PreToolUse-Agent", at: t0)
        try send("real-SubagentStart", at: t0 + 2)
        let main = try #require(try session(Self.mainID))
        let sub = try #require(try session(Self.agentID))
        #expect(sub.kind == .subagent)
        #expect(sub.parent === main)
        #expect(sub.agentName == "general-purpose")
        #expect(card.status == .active)

        try send("real-PostToolUse-Write-subagent", at: t0 + 4)
        let file = try #require((card.events ?? []).first { $0.type == .fileChanged })
        #expect(file.payloadValues["path"]?.stringValue == "note.txt")
        #expect(file.payloadValues["added"]?.intValue == 1)
        #expect(file.session === sub)

        try send("real-SubagentStop", at: t0 + 10)
        try send("real-UserPromptSubmit-agent-message", at: t0 + 10)
        #expect(sub.endedAt == t0 + 10)
        #expect(card.status == .next)
        #expect(main.endedAt == nil)
    }

    @Test func internalSubagentStopIsIgnored() throws {
        let (_, context) = try makeContext()
        // 내부 에이전트 훅이 난 폴더를 등록해 두어도 모르는 agent_id라 아무것도 만들지 않는다
        let project = Project(key: "TRK", name: "Waypoint", rootPath: "/Users/antaeho/workspace/projects/waypoint", createdAt: t0)
        context.insert(project)
        try context.save()
        let processor = HookProcessor(context: context, home: "/Users/antaeho", gitBranch: { _ in nil })
        processor.handle(event: nil, json: try fixture("real-SubagentStop-internal"), at: t0)
        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
    }

    @Test func resumeKeepsSessionIDAndRevivesEndedSession() throws {
        let (_, context) = try makeContext()
        let project = Project(key: "PRB", name: "훅 실측", rootPath: Self.root, createdAt: t0)
        context.insert(project)
        try context.save()
        let processor = HookProcessor(context: context, home: "/Users/antaeho", gitBranch: { _ in nil })
        // 같은 세션 ID로 끝난 뒤 resume
        let resume = try fixtureInput("real-SessionStart-resume")
        let start = HookInput(event: "SessionStart", object: ["session_id": resume.sessionID, "cwd": resume.cwd, "source": "startup"])!
        let end = HookInput(event: "SessionEnd", object: ["session_id": resume.sessionID, "cwd": resume.cwd, "reason": "other"])!
        processor.handle(start, at: t0)
        processor.handle(end, at: t0 + 10)
        processor.handle(resume, at: t0 + 60)
        let id = resume.sessionID
        let sessions = try context.fetch(FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id }))
        #expect(sessions.count == 1)
        #expect(sessions.first?.endedAt == nil)
        // fork는 새 세션 ID
        #expect(try fixtureInput("real-SessionStart-fork").sessionID != id)
    }
}
