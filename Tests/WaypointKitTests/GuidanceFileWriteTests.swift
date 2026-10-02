import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 프로젝트 밖 지침 파일 쓰기(TRK-41): 임시 폴더만 쓴다.
@Suite struct GuidanceFileWriteTests {
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    func perms(_ path: String) throws -> Int {
        try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
    }

    func store(_ dir: TempDir) -> GuidanceBackupStore {
        GuidanceBackupStore(root: dir.url.appendingPathComponent("support/guidance-backups"))
    }

    @Test func writeBacksUpThenWritesAtomically() throws {
        let dir = try TempDir()
        let file = try dir.write("home/.claude/CLAUDE.md", "- 하나\n- 둘\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        let backups = store(dir)
        let change = try GuidanceFileEdit.replacing(
            path: file.path, base: "- 하나\n- 둘\n", format: .markdown,
            item: try #require(GuidanceDocument.parse("- 하나\n- 둘\n", format: .markdown).item(id: [1])), with: "- 둘째"
        )
        try GuidanceFileWrite.apply([change], backups: backups, reason: .edit, at: date, checkRules: nil)
        #expect(try dir.read("home/.claude/CLAUDE.md") == "- 하나\n- 둘째\n")
        #expect(try perms(file.path) == 0o640)
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["CLAUDE.md"])

        let list = backups.backups(of: file.path)
        #expect(list.count == 1)
        #expect(list.first?.reason == .edit)
        #expect(list.first?.at == date, "\(String(describing: list.first?.at.timeIntervalSince1970)) \(String(describing: list.first?.url.lastPathComponent))")
        #expect(list.first?.url.lastPathComponent.hasSuffix("-edit.md") == true)
        #expect(String(data: try backups.content(of: try #require(list.first)), encoding: .utf8) == "- 하나\n- 둘\n")
        // 권한: 폴더 0700, 파일 0600
        #expect(try perms(backups.root.path) == 0o700)
        #expect(try perms(backups.folder(for: file.path).path) == 0o700)
        #expect(try perms(try #require(list.first).url.path) == 0o600)
        let meta = backups.folder(for: file.path).appendingPathComponent(GuidanceBackupStore.metaName)
        #expect(try perms(meta.path) == 0o600)
        #expect(backups.backedUpPaths() == [file.path])
    }

    @Test func keepsLatestFifty() throws {
        let dir = try TempDir()
        let backups = store(dir)
        let path = dir.url.appendingPathComponent("rules/default.rules").path
        for i in 0..<55 {
            try backups.save(Data("판 \(i)".utf8), of: path, reason: .edit, at: date.addingTimeInterval(Double(i)))
        }
        let list = backups.backups(of: path)
        #expect(list.count == GuidanceBackupStore.limit)
        #expect(String(data: try backups.content(of: list[0]), encoding: .utf8) == "판 54")
        #expect(String(data: try backups.content(of: list[49]), encoding: .utf8) == "판 5")
        #expect(list[0].url.pathExtension == "rules")
    }

    @Test func sameMillisecondKeepsOrder() throws {
        let dir = try TempDir()
        let backups = store(dir)
        let path = dir.url.appendingPathComponent("a.md").path
        try backups.save(Data("1".utf8), of: path, reason: .edit, at: date)
        try backups.save(Data("2".utf8), of: path, reason: .delete, at: date)
        let list = backups.backups(of: path)
        #expect(list.map(\.reason) == [.delete, .edit])
        #expect(String(data: try backups.content(of: list[0]), encoding: .utf8) == "2")
    }

    @Test func restoreBacksUpCurrentFirst() throws {
        let dir = try TempDir()
        let file = try dir.write("CLAUDE.md", "옛\n")
        let backups = store(dir)
        try GuidanceFileWrite.apply([.init(path: file.path, before: "옛\n", after: "새\n")],
                                    backups: backups, reason: .edit, at: date, checkRules: nil)
        let old = try #require(backups.backups(of: file.path).first)
        try GuidanceFileWrite.restore(old, backups: backups, at: date + 1)
        #expect(try dir.read("CLAUDE.md") == "옛\n")
        let list = backups.backups(of: file.path)
        #expect(list.map(\.reason) == [.restore, .edit])
        #expect(String(data: try backups.content(of: list[0]), encoding: .utf8) == "새\n")
    }

    @Test func restoreRecreatesDeletedFile() throws {
        let dir = try TempDir()
        let file = try dir.write("memory/a.md", "---\nname: a\n---\n본문\n")
        let backups = store(dir)
        try GuidanceFileWrite.apply([.init(path: file.path, before: "---\nname: a\n---\n본문\n", after: nil)],
                                    backups: backups, reason: .delete, at: date, checkRules: nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let backup = try #require(backups.backups(of: file.path).first)
        try GuidanceFileWrite.restore(backup, backups: backups, at: date + 1)
        #expect(try dir.read("memory/a.md") == "---\nname: a\n---\n본문\n")
        // 없던 파일이라 되돌리기 전 백업은 없다
        #expect(backups.backups(of: file.path).count == 1)
    }

    @Test func changedOnDiskIsRefused() throws {
        let dir = try TempDir()
        let file = try dir.write("CLAUDE.md", "- 하나\n")
        let backups = store(dir)
        try dir.write("CLAUDE.md", "- 하나\n- 밖에서 더함\n")
        #expect(throws: GuidanceFileWrite.Failure.changed) {
            try GuidanceFileWrite.apply([.init(path: file.path, before: "- 하나\n", after: "- 바꿈\n")],
                                        backups: backups, reason: .edit, at: date, checkRules: nil)
        }
        #expect(try dir.read("CLAUDE.md") == "- 하나\n- 밖에서 더함\n")
        #expect(backups.backups(of: file.path).isEmpty)
        // 사라진 파일도 바뀐 것
        try FileManager.default.removeItem(at: file)
        #expect(throws: GuidanceFileWrite.Failure.changed) {
            try GuidanceFileWrite.apply([.init(path: file.path, before: "- 하나\n", after: "- 바꿈\n")],
                                        backups: backups, reason: .edit, at: date, checkRules: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// 여러 파일 중 하나라도 바뀌었으면 아무것도 쓰지 않는다.
    @Test func changedSecondFileWritesNothing() throws {
        let dir = try TempDir()
        let a = try dir.write("memory/a.md", "A\n")
        let index = try dir.write("memory/MEMORY.md", "- [a](a.md)\n")
        try dir.write("memory/MEMORY.md", "- [a](a.md)\n- [b](b.md)\n")
        #expect(throws: GuidanceFileWrite.Failure.changed) {
            try GuidanceFileWrite.apply([.init(path: a.path, before: "A\n", after: nil),
                                         .init(path: index.path, before: "- [a](a.md)\n", after: "")],
                                        backups: store(dir), reason: .delete, at: date, checkRules: nil)
        }
        #expect(try dir.read("memory/a.md") == "A\n")
    }

    // MARK: - 기억 지우기

    static let index = """
    # 기억

    - [첫째](a.md) — 첫째 설명
    - [둘째](b.md) — 둘째 설명
    - [없는 파일](gone.md) — 사라진 기억

    """

    func memoryFolder() throws -> (TempDir, URL, URL, URL) {
        let dir = try TempDir()
        let a = try dir.write("memory/a.md", "---\nname: 첫째\ndescription: 첫째 설명\n---\n\n본문 A\n")
        let b = try dir.write("memory/b.md", "---\nname: 둘째\n---\n본문 B\n")
        let index = try dir.write("memory/MEMORY.md", Self.index)
        return (dir, a, b, index)
    }

    @Test func deletingMemoryRemovesFileAndIndexLineThenUndo() throws {
        let (dir, a, _, index) = try memoryFolder()
        let backups = store(dir)
        let base = try dir.read("memory/a.md")
        let item = try #require(GuidanceDocument.parse(base, format: .memory).items.first)
        let set = try GuidanceFileEdit.removing(path: a.path, base: base, format: .memory, item: item)
        #expect(set.changes.map(\.path) == [a.path, index.path])
        #expect(set.indexLines == 1)
        #expect(set.summary == "지움 · 첫째 설명 · 색인 줄 포함")
        try GuidanceFileWrite.apply(set.changes, backups: backups, reason: .delete, at: date, checkRules: nil)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(try dir.read("memory/MEMORY.md") == """
        # 기억

        - [둘째](b.md) — 둘째 설명
        - [없는 파일](gone.md) — 사라진 기억

        """)
        #expect(backups.backups(of: a.path).map(\.reason) == [.delete])
        #expect(backups.backups(of: index.path).map(\.reason) == [.delete])

        // 되돌리기: 둘 다 원래대로(바이트까지)
        try GuidanceFileWrite.apply(set.inverted.changes, backups: backups, reason: .undo, at: date + 1, checkRules: nil)
        #expect(try dir.read("memory/a.md") == base)
        #expect(try dir.read("memory/MEMORY.md") == Self.index)
        #expect(backups.backups(of: index.path).map(\.reason) == [.undo, .delete])
    }

    @Test func undoAfterIndexChangedIsRefused() throws {
        let (dir, a, _, _) = try memoryFolder()
        let backups = store(dir)
        let base = try dir.read("memory/a.md")
        let item = try #require(GuidanceDocument.parse(base, format: .memory).items.first)
        let set = try GuidanceFileEdit.removing(path: a.path, base: base, format: .memory, item: item)
        try GuidanceFileWrite.apply(set.changes, backups: backups, reason: .delete, at: date, checkRules: nil)
        try dir.write("memory/MEMORY.md", "다른 내용\n")
        #expect(throws: GuidanceFileWrite.Failure.changed) {
            try GuidanceFileWrite.apply(set.inverted.changes, backups: backups, reason: .undo, at: date + 1, checkRules: nil)
        }
        // 파일도 되살리지 않았다(먼저 모두 확인)
        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    @Test func deletingUnindexedMemoryRemovesFileOnly() throws {
        let (dir, _, _, _) = try memoryFolder()
        let c = try dir.write("memory/c.md", "색인 없는 기억\n")
        let set = try GuidanceFileEdit.removingMemory(path: c.path, base: "색인 없는 기억\n", preview: "색인 없는 기억")
        #expect(set.changes.map(\.path) == [c.path])
        #expect(set.indexLines == 0)
        try GuidanceFileWrite.apply(set.changes, backups: store(dir), reason: .delete, at: date, checkRules: nil)
        #expect(!FileManager.default.fileExists(atPath: c.path))
        #expect(try dir.read("memory/MEMORY.md") == Self.index)
    }

    @Test func deletingMemoryWithoutIndexFile() throws {
        let dir = try TempDir()
        let a = try dir.write("memory/a.md", "A\n")
        let set = try GuidanceFileEdit.removingMemory(path: a.path, base: "A\n", preview: "A")
        #expect(set.changes.count == 1)
        try GuidanceFileWrite.apply(set.changes, backups: store(dir), reason: .delete, at: date, checkRules: nil)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("memory/MEMORY.md").path))
    }

    @Test func deletingOrphanIndexLineOnly() throws {
        let (dir, _, _, index) = try memoryFolder()
        let document = GuidanceDocument.parse(Self.index, format: .memoryIndex)
        let orphan = try #require(document.items.first { $0.link == "gone.md" })
        let set = try GuidanceFileEdit.removing(path: index.path, base: Self.index, format: .memoryIndex, item: orphan)
        #expect(set.changes.map(\.path) == [index.path])
        try GuidanceFileWrite.apply(set.changes, backups: store(dir), reason: .delete, at: date, checkRules: nil)
        #expect(try dir.read("memory/MEMORY.md") == """
        # 기억

        - [첫째](a.md) — 첫째 설명
        - [둘째](b.md) — 둘째 설명

        """)
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("memory/a.md").path))
    }

    @Test func removesEveryIndexLineForFile() {
        let index = "- [a](a.md)\n- [b](b.md)\n- [a 다시](./a.md#절)\n"
        let result = GuidanceFileEdit.removingIndexLines(index, pointingTo: "a.md")
        #expect(result.count == 2)
        #expect(result.content == "- [b](b.md)\n")
    }

    @Test func ambiguousIndexIsLeftAlone() {
        let index = "<div>\n- [a](a.md)\n</div>\n"
        let result = GuidanceFileEdit.removingIndexLines(index, pointingTo: "a.md")
        #expect(result.count == 0)
        #expect(result.content == index)
    }

    @Test func editingMemoryContent() throws {
        let (dir, a, _, _) = try memoryFolder()
        let base = try dir.read("memory/a.md")
        let item = try #require(GuidanceDocument.parse(base, format: .memory).items.first)
        let next = "---\nname: 첫째\ndescription: 바꾼 설명\n---\n\n본문 A\n"
        let change = try GuidanceFileEdit.replacing(path: a.path, base: base, format: .memory, item: item,
                                                    with: String(next.dropLast()))
        try GuidanceFileWrite.apply([change], backups: store(dir), reason: .edit, at: date, checkRules: nil)
        #expect(try dir.read("memory/a.md") == next)
    }

    // MARK: - Codex 기억 DB

    @Test func codexMemoryHasNoWritePath() throws {
        let dir = try TempDir()
        let db = try dir.write("codex/\(CodexMemoryStore.fileName)", "SQLite format 3")
        #expect(!GuidanceFileWrite.isWritable(kind: .codexMemory, path: db.path))
        #expect(!GuidanceFileWrite.writableKinds.contains(.codexMemory))
        // 종류를 속여도 경로로 거절
        #expect(!GuidanceFileWrite.isWritable(kind: .global, path: db.path))
        for path in [db.path, db.path + "-wal", dir.url.appendingPathComponent("codex/other.sqlite").path] {
            #expect(throws: GuidanceFileWrite.Failure.notWritable) {
                try GuidanceFileWrite.apply([.init(path: path, before: "SQLite format 3", after: "x")],
                                            backups: store(dir), reason: .edit, at: date, checkRules: nil)
            }
        }
        #expect(try dir.read("codex/\(CodexMemoryStore.fileName)") == "SQLite format 3")
        #expect(!GuidanceFileWrite.isWritable(kind: .global, path: "/Library/Application Support/ClaudeCode/CLAUDE.md"))
    }

    // MARK: - 규칙 파일

    @Test func invalidRulesAreNotSaved() throws {
        let dir = try TempDir()
        let good = "prefix_rule(pattern=[\"ls\"], decision=\"allow\")\n"
        let file = try dir.write("codex/rules/default.rules", good)
        let backups = store(dir)
        let bad = good + "prefix_rule(pattern=[\"git\"\n"
        #expect {
            try GuidanceFileWrite.apply([.init(path: file.path, before: good, after: bad)],
                                        backups: backups, reason: .edit, at: date,
                                        checkRules: { CommandRulesCheck.builtIn($0) })
        } throws: { error in
            guard case GuidanceFileWrite.Failure.invalidRules(let outcome) = error else { return false }
            return outcome.line == 2 && outcome.method == .builtIn
        }
        #expect(try dir.read("codex/rules/default.rules") == good)
        #expect(backups.backups(of: file.path).isEmpty)
        // 맞는 내용은 저장
        let more = good + "prefix_rule(pattern=[\"git\", \"status\"], decision=\"allow\")\n"
        try GuidanceFileWrite.apply([.init(path: file.path, before: good, after: more)],
                                    backups: backups, reason: .edit, at: date, checkRules: { CommandRulesCheck.builtIn($0) })
        #expect(try dir.read("codex/rules/default.rules") == more)
    }
}

/// 규칙 파일 자체 검사와 Codex 검사.
@Suite struct CommandRulesCheckTests {
    static let good = """
    # 주석
    prefix_rule(pattern=["git", "status"], decision="allow")
    prefix_rule(
        pattern=["ls", "-la"],
        decision="allow",
    )

    """

    @Test func builtInAcceptsGoodFiles() {
        #expect(CommandRulesCheck.builtIn(Self.good).isValid)
        #expect(CommandRulesCheck.builtIn("").isValid)
        #expect(CommandRulesCheck.builtIn("# 주석만\n").isValid)
        #expect(CommandRulesCheck.builtIn("host_executable(name=\"git\", paths=[\"/usr/bin/git\"])  # 끝 주석\n").isValid)
    }

    @Test func builtInRejectsBadLines() {
        let cases: [(String, Int?)] = [
            ("prefix_rule(pattern=[\"a\"], decision=\"allow\")\nprefix_rule(pattern=[\"b\"\n", 2),
            ("prefix_rule(pattern=[\"a\"]))\n", 1),
            ("prefix_rul(pattern=[\"a\"], decision=\"allow\")\n", 1),
            ("# 주석\nallow ls\n", 2),
            ("prefix_rule(pattern=[\"a\"], decision=\"allow\") extra\n", 1),
            ("prefix_rule(pattern=[\"a], decision=\"allow\")\n", 1),
        ]
        for (content, line) in cases {
            let outcome = CommandRulesCheck.builtIn(content)
            #expect(!outcome.isValid, "\(content)")
            #expect(outcome.line == line, "\(content): \(String(describing: outcome.message))")
            #expect(outcome.method == .builtIn)
        }
    }

    @Test func parsesCodexErrorOutput() {
        let parse = """
        Error: failed to parse policy at check.rules

        Caused by:
            starlark error: error: Parse error: unexpected new line, expected symbol ']'
            --> check.rules:1:1
             |
             |

        """
        let first = CommandRulesCheck.parseError(parse, fileName: "check.rules")
        #expect(first.message == "Parse error: unexpected new line, expected symbol ']'")
        #expect(first.line == nil)
        let value = """
        Error: failed to parse policy at check.rules

        Caused by:
            error: invalid decision: maybe
             --> check.rules:3:1
              |
            3 | prefix_rule(pattern=["git"], decision="maybe")
              | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
              |

        """
        let second = CommandRulesCheck.parseError(value, fileName: "check.rules")
        #expect(second.message == "invalid decision: maybe")
        #expect(second.line == 3)
        #expect(CommandRulesCheck.Outcome(method: .codex, problem: second.message, line: 3).message == "줄 3 · invalid decision: maybe")
    }

    #if os(macOS)
    static var codex: String? { CommandRulesCheck.findCodex() }

    /// 실제 Codex CLI(있을 때만). 임시 파일과 임시 `CODEX_HOME`만 쓴다.
    @Test(.enabled(if: codex != nil)) func codexChecksGoodAndBadFiles() throws {
        let codex = try #require(Self.codex)
        let good = try #require(CommandRulesCheck.run(codex: codex, content: Self.good))
        #expect(good == .init(method: .codex))
        let empty = try #require(CommandRulesCheck.run(codex: codex, content: ""))
        #expect(empty.isValid)
        // 검사 명령을 막는 규칙이 있어도 파일은 맞다
        let forbid = try #require(CommandRulesCheck.run(codex: codex, content: "prefix_rule(pattern=[\"true\"], decision=\"forbidden\")\n"))
        #expect(forbid.isValid)

        let decision = try #require(CommandRulesCheck.run(
            codex: codex, content: "prefix_rule(pattern=[\"a\"], decision=\"allow\")\nprefix_rule(pattern=[\"git\"], decision=\"maybe\")\n"))
        #expect(!decision.isValid)
        #expect(decision.line == 2)
        #expect(decision.problem?.contains("maybe") == true)

        let unclosed = try #require(CommandRulesCheck.run(codex: codex, content: "prefix_rule(pattern=[\"ls\"\n"))
        #expect(!unclosed.isValid)
        #expect(unclosed.method == .codex)

        let unknown = try #require(CommandRulesCheck.run(codex: codex, content: "prefix_rul(pattern=[\"ls\"])\n"))
        #expect(!unknown.isValid)
        #expect(unknown.line == 1)
    }

    /// 실행 파일이 없을 때(nil)만 자체 검사로 대신한다.
    @Test func missingCodexFallsBackToBuiltIn() {
        let outcome = CommandRulesCheck.check("prefix_rule(pattern=[\"ls\"\n", codex: nil)
        #expect(outcome.method == .builtIn)
        #expect(!outcome.isValid)
        #expect(CommandRulesCheck.check(Self.good, codex: nil) == .init(method: .builtIn))
    }

    /// 실행 파일이 있는데 실행하지 못하면 맞는 내용이어도 저장하지 않는다.
    @Test func launchFailureBlocksSave() throws {
        let dir = try TempDir()
        // 실행 권한 없는 파일, 없는 경로
        let notExecutable = try dir.write("codex", "#!/bin/sh\nexit 0\n")
        for codex in [notExecutable.path, dir.url.appendingPathComponent("none/codex").path] {
            let outcome = CommandRulesCheck.check(Self.good, codex: codex)
            #expect(outcome == .unchecked, "\(codex)")
            #expect(!outcome.isValid)
        }
        let file = try dir.write("rules/default.rules", "")
        #expect(throws: GuidanceFileWrite.Failure.invalidRules(.unchecked)) {
            try GuidanceFileWrite.apply([.init(path: file.path, before: "", after: Self.good)],
                                        backups: GuidanceBackupStore(root: dir.url.appendingPathComponent("b")),
                                        reason: .edit, at: Date(),
                                        checkRules: { CommandRulesCheck.check($0, codex: notExecutable.path) })
        }
        #expect(try dir.read("rules/default.rules") == "")
    }

    /// 시간 안에 끝나지 않는 가짜 codex는 멈추고 저장하지 않는다.
    @Test func timeoutBlocksSave() throws {
        let dir = try TempDir()
        let slow = try dir.write("codex", "#!/bin/sh\nsleep 5\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slow.path)
        let start = Date()
        let outcome = CommandRulesCheck.check(Self.good, codex: slow.path, timeout: 0.5)
        #expect(outcome == .unchecked)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// 가짜 codex가 바로 0으로 끝나면 통과(실행 경로 자체는 쓰인다).
    @Test func fakeCodexSuccess() throws {
        let dir = try TempDir()
        let fake = try dir.write("codex", "#!/bin/sh\nexit 0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        #expect(CommandRulesCheck.check("아무 글", codex: fake.path) == .init(method: .codex))
    }
    #endif
}

/// 열린 세션 수.
@Suite struct GuidanceOpenSessionsTests {
    @Test func countsOpenMainSessionsOfTool() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx, key: "AAA")
        let q = makeProject(ctx, key: "BBB")
        func session(_ id: String, _ provider: AgentProvider, _ project: Project?, ended: Bool = false,
                     kind: SessionKind = .main) -> Session {
            let s = Session(id: id, kind: kind, provider: provider)
            ctx.insert(s)
            s.project = project
            if ended { s.endedAt = Date() }
            return s
        }
        let sessions = [
            session("1", .claude, p), session("2", .claude, q), session("3", .claude, p, ended: true),
            session("4", .claude, p, kind: .subagent), session("5", .codex, p), session("6", .claude, nil),
        ]
        let global = GuidanceSource(kind: .global, tool: .claude, path: "/h/.claude/CLAUDE.md", scope: .global)
        #expect(GuidanceOpenSessions.count(for: global, sessions: sessions) == 3)
        let ancestor = GuidanceSource(kind: .ancestor, tool: .claude, path: "/h/w/CLAUDE.md", scope: .ancestor("/h/w"),
                                      appliesTo: ["AAA"])
        #expect(GuidanceOpenSessions.count(for: ancestor, sessions: sessions) == 1)
        let rules = GuidanceSource(kind: .commandRules, tool: .codex, path: "/h/.codex/rules/default.rules", scope: .global)
        #expect(GuidanceOpenSessions.count(for: rules, sessions: sessions) == 1)
        #expect(GuidanceOpenSessions.label(for: rules, count: 1) == "열린 Codex 세션 1")
        #expect(GuidanceOpenSessions.label(for: global, count: 0) == nil)
    }
}
