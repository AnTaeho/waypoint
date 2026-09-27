import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct HookParsingTests {

    @Test func fixturesDecode() throws {
        let names = [
            "doc-SessionStart", "doc-SessionStart-unregistered", "doc-UserPromptSubmit", "doc-PreToolUse-Agent",
            "doc-SubagentStart", "doc-PostToolUse-Edit", "doc-PostToolUse-Write-subagent",
            "doc-PostToolUse-Bash-commit", "doc-SubagentStop", "doc-Stop", "doc-SessionEnd",
        ]
        for name in names {
            let input = try fixtureInput(name)
            #expect(!input.sessionID.isEmpty, "\(name)")
            #expect(!input.cwd.isEmpty, "\(name)")
        }
        #expect(try fixtureInput("doc-SessionStart").source == "startup")
        #expect(try fixtureInput("doc-SubagentStart").agentID == "a4d2c8f1e0b3a297")
        #expect(try fixtureInput("doc-SessionEnd").reason == "prompt_input_exit")
        #expect(try fixtureInput("doc-PreToolUse-Agent").toolName == "Agent")
    }

    @Test func pathEventNameWinsOverBody() throws {
        let input = try #require(HookInput(event: "Stop", json: try fixture("doc-SessionEnd")))
        #expect(input.event == "Stop")
        #expect(try fixtureInput("doc-SessionEnd").event == "SessionEnd")
    }

    @Test func cardReferences() {
        let refs = HookParsing.cardReferences(in: "[LDG-16] 테스트, 참고 [WEB-3] 그리고 LDG-9는 괄호 없음 [ldg-1]")
        #expect(refs.map(\.key) == ["LDG", "WEB"])
        #expect(refs.map(\.number) == [16, 3])
    }

    @Test func lineCount() {
        #expect(HookParsing.lineCount("") == 0)
        #expect(HookParsing.lineCount("a") == 1)
        #expect(HookParsing.lineCount("a\n") == 1)
        #expect(HookParsing.lineCount("a\nb") == 2)
        #expect(HookParsing.lineCount("a\n\nb\n") == 3)
    }

    @Test func commitOutputs() throws {
        let commit = try #require(HookParsing.commit(try fixtureInput("doc-PostToolUse-Bash-commit")))
        #expect(commit.branch == "feat/ocr-mapping")
        #expect(commit.hash == "4c1d9e0")

        func bash(_ command: String, _ stdout: String) -> HookInput {
            HookInput(event: "PostToolUse", object: [
                "session_id": "s", "cwd": "/x", "tool_name": "Bash",
                "tool_input": ["command": command], "tool_response": ["stdout": stdout],
            ])!
        }
        let root = HookParsing.commit(bash("git commit -m init", "[main (root-commit) abc1234] init\n"))
        #expect(root?.branch == "main")
        #expect(root?.hash == "abc1234")
        let detached = HookParsing.commit(bash("git commit -am x", "[detached HEAD 1234567] x"))
        #expect(detached?.branch == nil)
        #expect(detached?.hash == "1234567")
        #expect(HookParsing.commit(bash("git status", "[main abc1234] x")) == nil)
        #expect(HookParsing.commit(bash("git commit -m x", "nothing to commit")) == nil)
    }

    @Test func bashEditDiffFiles() {
        let input = HookInput(event: "PostToolUse", object: [
            "session_id": "s", "cwd": "/x", "tool_name": "Bash",
            "tool_input": ["command": "sed -i s/a/b/ f.txt"],
            "tool_response": ["stdout": "", "bashEditDiff": ["changedFiles": ["/x/f.txt"]]],
        ])!
        let files = HookParsing.changedFiles(input)
        #expect(files.map(\.path) == ["/x/f.txt"])
    }
}

@Suite struct ProjectMatcherTests {
    let home = "/Users/me"

    @Test func nearestRootWins() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let outer = Project(key: "OUT", name: "바깥", rootPath: "~/dev")
        let inner = Project(key: "LDG", name: "가계부", rootPath: "/Users/me/dev/ledger/")
        let archived = Project(key: "OLD", name: "옛것", rootPath: "~/dev/ledger/Ledger")
        archived.archivedAt = t0
        for p in [outer, inner, archived] { ctx.insert(p) }
        let all = [outer, inner, archived]
        #expect(ProjectMatcher.project(for: "/Users/me/dev/ledger/Ledger/OCR", in: all, home: home) === inner)
        #expect(ProjectMatcher.project(for: "/Users/me/dev/ledger", in: all, home: home) === inner)
        #expect(ProjectMatcher.project(for: "/Users/me/dev/ledger2", in: all, home: home) === outer)
        #expect(ProjectMatcher.project(for: "/Users/me/other", in: all, home: home) == nil)
        #expect(ProjectMatcher.project(for: "", in: all, home: home) == nil)
    }

    @Test func relativePaths() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = Project(key: "LDG", name: "가계부", rootPath: "~/dev/ledger")
        ctx.insert(p)
        #expect(ProjectMatcher.relativePath("/Users/me/dev/ledger/Ledger/A.swift", in: p, home: home) == "Ledger/A.swift")
        #expect(ProjectMatcher.relativePath("/tmp/B.swift", in: p, home: home) == "/tmp/B.swift")
    }

    @Test func gitBranchFromHead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-git-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("src/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/x\n".write(to: dir.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitInfo.branch(at: sub.path) == "feat/x")
        try "0123456789abcdef\n".write(to: dir.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitInfo.branch(at: sub.path) == nil)
    }
}
