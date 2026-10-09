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
        #expect(refs.map { $0.key } == ["LDG", "WEB"])
        #expect(refs.map { $0.number } == [16, 3])
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

    // PID는 32비트 최댓값까지 받고 그보다 크면 버린다.
    @Test func pidAcceptsUpToInt32Max() {
        let top = Int(Int32.max)
        #expect(HookParsing.pid(top) == top)
        #expect(HookParsing.pid("\(top)") == top)
        #expect(HookParsing.pid(top + 1) == nil)
        #expect(HookParsing.pid(2) == 2)
        #expect(HookParsing.pid(1) == nil)
    }

    // MultiEdit는 조각마다의 줄 수를 더한다.
    @Test func multiEditSumsLinesAcrossEdits() {
        let input = HookInput(event: "PostToolUse", object: [
            "session_id": "s", "cwd": "/x", "tool_name": "MultiEdit",
            "tool_input": ["file_path": "/x/f.swift", "edits": [
                ["old_string": "a\nb", "new_string": "c"],
                ["old_string": "d", "new_string": "e\nf\ng"],
            ]],
        ])!
        let files = HookParsing.changedFiles(input)
        #expect(files.map { $0.path } == ["/x/f.swift"])
        #expect(files.first?.added == 4 && files.first?.removed == 3)
    }

    // 커밋 결과의 긴 해시와 출력 줄의 짧은 해시가 앞부분만 같아도 그 줄의 메시지를 쓴다.
    @Test func commitMessageMatchesAbbreviatedHash() {
        func commit(sha: String, stdout: String) -> (branch: String?, hash: String, message: String)? {
            HookParsing.commit(HookInput(event: "PostToolUse", object: [
                "session_id": "s", "cwd": "/x", "tool_name": "Bash", "tool_input": ["command": "git commit -m x"],
                "tool_response": ["stdout": stdout, "gitOperation": ["commit": ["sha": sha, "branch": "main"]]],
            ])!)
        }
        let long = commit(sha: "abc1234def5678900000", stdout: "[main abc1234] 합계 규칙\n")
        #expect(long?.hash == "abc1234def5678900000" && long?.message == "합계 규칙")
        let short = commit(sha: "abc1234", stdout: "[main abc1234def56] 합계 규칙\n")
        #expect(short?.message == "합계 규칙")
        #expect(commit(sha: "fff0000", stdout: "[main abc1234] 다른 커밋\n")?.message == "")
    }

    // `git -c …` 뒤에 commit이 올 때만 커밋으로 본다.
    @Test func gitConfigFlagAloneIsNotACommit() {
        func bash(_ command: String) -> HookInput {
            HookInput(event: "PostToolUse", object: [
                "session_id": "s", "cwd": "/x", "tool_name": "Bash",
                "tool_input": ["command": command], "tool_response": ["stdout": "[main abc1234] x\n"],
            ])!
        }
        #expect(HookParsing.commit(bash("git -c user.name=me commit -m x"))?.hash == "abc1234")
        #expect(HookParsing.commit(bash("git -c color.ui=never log -1")) == nil)
        #expect(HookParsing.commit(bash("echo 'ready to commit'")) == nil)
    }

    @Test func bashEditDiffFiles() {
        let input = HookInput(event: "PostToolUse", object: [
            "session_id": "s", "cwd": "/x", "tool_name": "Bash",
            "tool_input": ["command": "sed -i s/a/b/ f.txt"],
            "tool_response": ["stdout": "", "bashEditDiff": ["changedFiles": ["/x/f.txt"]]],
        ])!
        let files = HookParsing.changedFiles(input)
        #expect(files.map { $0.path } == ["/x/f.txt"])
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

    // 최상위 폴더(`/`)는 그대로 두고, `/`에 등록한 프로젝트는 그 아래 모든 경로를 받는다.
    @Test func rootFolderIsKeptAsSlash() throws {
        #expect(ProjectMatcher.normalize("/") == "/")
        let (_c, ctx) = try makeContext(); _ = _c
        let whole = Project(key: "ALL", name: "전체", rootPath: "/")
        ctx.insert(whole)
        #expect(ProjectMatcher.nearest(for: "/srv/app", in: [whole], home: home) === whole)
    }

    // 빈 최상위 경로는 어떤 경로도 품지 않는다.
    @Test func emptyRootContainsNothing() {
        #expect(!ProjectMatcher.isInside("/Users/me/dev", root: ""))
        #expect(!ProjectMatcher.isInside("", root: ""))
    }

    // 파일 시스템 최상위가 git 작업 트리면 `/`를 돌려준다.
    @Test func checkoutAtFilesystemRootIsSlash() {
        final class RootRepository: FileManager {
            override func fileExists(atPath path: String) -> Bool { path == "/.git" }
        }
        #expect(GitInfo.checkoutRoot(for: "/notes.txt", fileManager: RootRepository()) == "/")
        #expect(GitInfo.checkoutRoot(for: "/srv/app/notes.txt", fileManager: RootRepository()) == "/")
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
