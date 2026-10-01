import Foundation
import Testing
@testable import WaypointKit

@Suite struct MemoryFolderNameTests {
    @Test func everyNonAlphanumericBecomesDash() {
        #expect(MemoryFolderName.encode("/Users/antaeho/workspace") == "-Users-antaeho-workspace")
        // 실제 폴더: credit_system → credit-system
        #expect(MemoryFolderName.encode("/Users/antaeho/workspace/projects/credit_system")
                == "-Users-antaeho-workspace-projects-credit-system")
        #expect(MemoryFolderName.encode("/Users/me/.claude/x y") == "-Users-me--claude-x-y")
        #expect(MemoryFolderName.encode("/Users/me/작업") == "-Users-me---")
    }

    @Test func longNamesMatchByPrefix() {
        let path = "/Users/me/" + String(repeating: "a", count: 230)
        let encoded = MemoryFolderName.encode(path)
        let name = String(encoded.prefix(200)) + "-1a2b3c"
        #expect(MemoryFolderName.matches(name, path: path))
        #expect(!MemoryFolderName.matches(encoded, path: "/Users/me/other"))
        #expect(!MemoryFolderName.matches(String(encoded.prefix(200)), path: path))
    }

    @Test func locateWalksRealFolders() {
        let fs = FakeGuidanceFileSystem()
            .directory("/Users/me/workspace/projects/credit_system")
            .directory("/Users/me/workspace/projects/credit-system-kotlin")
            .directory("/Users/me/.claude/x")
        let found = MemoryFolderName.locate("-Users-me-workspace-projects-credit-system", fileSystem: fs)
        #expect(found.path == "/Users/me/workspace/projects/credit_system")
        #expect(found.onDisk)
        #expect(MemoryFolderName.locate("-Users-me--claude-x", fileSystem: fs) == ("/Users/me/.claude/x", true))
    }

    @Test func locateFallsBackToEstimate() {
        let fs = FakeGuidanceFileSystem().directory("/Users/me")
        let found = MemoryFolderName.locate("-Users-me-gone-app", fileSystem: fs)
        #expect(found.path == "/Users/me/gone/app")
        #expect(!found.onDisk)
    }
}

@Suite struct GuidanceCollectorTests {
    let home = "/Users/me"

    /// 이 Mac과 비슷한 배치: 프로젝트 둘(TRK는 git), 상위 폴더 지침, 기억 폴더 다섯(빈 것 하나).
    func machine() -> FakeGuidanceFileSystem {
        let fs = FakeGuidanceFileSystem()
        fs.file("/Users/me/.claude/CLAUDE.md", "# 전역\n- a\n- b\n")
        fs.file("/Users/me/.claude/rules/style.md", "규칙\n")
        fs.file("/Users/me/workspace/CLAUDE.md", "# 작업 폴더\n")
        fs.file("/Users/me/workspace/AGENTS.md", "상위\n")
        fs.directory("/Users/me/workspace/projects/waypoint/.git")
        fs.file("/Users/me/workspace/projects/waypoint/CLAUDE.md", "한\n\n둘\n")
        fs.file("/Users/me/workspace/projects/waypoint/.claude/CLAUDE.md", "로컬 설정\n")
        fs.file("/Users/me/workspace/projects/waypoint/CLAUDE.local.md", "나만\n")
        fs.file("/Users/me/workspace/projects/waypoint/AGENTS.md", "codex\n")
        fs.file("/Users/me/workspace/projects/waypoint/.claude/rules/api/a.md", "a\n")
        fs.file("/Users/me/workspace/projects/credit_system/AGENTS.md", "c\n")
        fs.directory("/Users/me/workspace/job")
        let p = "/Users/me/.claude/projects/"
        fs.file(p + "-Users-me-workspace/memory/MEMORY.md", "- [a](a.md) — 하나\n- [b](b.md) — 둘\n")
        fs.file(p + "-Users-me-workspace/memory/a.md", "---\nname: a\n---\n본문\n")
        fs.file(p + "-Users-me-workspace-projects-waypoint/memory/MEMORY.md", "- [x](x.md)\n")
        fs.file(p + "-Users-me-workspace-projects-waypoint/memory/x.md", "x\n")
        fs.file(p + "-Users-me-workspace-projects-waypoint/abc.jsonl", "{}\n")
        fs.file(p + "-Users-me-workspace-projects-credit-system/memory/MEMORY.md", "- [c](c.md)\n")
        fs.file(p + "-Users-me-workspace-job/memory/MEMORY.md", "- j\n")
        fs.file(p + "-Users-me-workspace-old-app/memory/note.md", "옛\n")
        fs.directory(p + "-Users-me-workspace-projects-empty/memory")
        fs.file("/Users/me/.codex/rules/default.rules", "# 주석\nprefix_rule(a)\nprefix_rule(b)\n")
        fs.file("/Users/me/.codex/memories_1.sqlite", "db")
        fs.file("/Users/me/.codex/logs_2.sqlite", "log")
        return fs
    }

    func collector(_ fs: FakeGuidanceFileSystem) -> GuidanceCollector {
        GuidanceCollector(home: home, fileSystem: fs, codexMemoryCount: { _ in 3 })
    }

    let projects = [
        GuidanceProject(key: "TRK", rootPath: "/Users/me/workspace/projects/waypoint"),
        GuidanceProject(key: "CHM", rootPath: "~/workspace/projects/credit_system"),
    ]

    func source(_ snapshot: GuidanceSnapshot, _ path: String) throws -> GuidanceSource {
        try #require(snapshot.sources.first { $0.path == path })
    }

    @Test func globalSources() throws {
        let fs = machine()
        let snapshot = collector(fs).collect(projects: projects)
        let global = snapshot.sources(in: .global)
        #expect(global.map(\.path) == [
            "/Users/me/.claude/CLAUDE.md", "/Users/me/.claude/rules/style.md",
            "/Users/me/.codex/memories_1.sqlite", "/Users/me/.codex/rules/default.rules",
        ])
        #expect(try source(snapshot, "/Users/me/.claude/CLAUDE.md").entryCount == 3)
        // 홈이 상위 폴더여도 `~/.claude/CLAUDE.md`는 전역 그대로
        #expect(global.allSatisfy { $0.appliesTo.isEmpty })
        let rules = try source(snapshot, "/Users/me/.codex/rules/default.rules")
        #expect(rules.kind == .commandRules && rules.tool == .codex && rules.entryCount == 2)
        let db = try source(snapshot, "/Users/me/.codex/memories_1.sqlite")
        #expect(db.kind == .codexMemory && db.entryCount == 3)
    }

    @Test func projectAndAncestorSources() throws {
        let snapshot = collector(machine()).collect(projects: projects)
        let trk = snapshot.sources(in: .project("TRK")).filter { !$0.isMemory }.map(\.path)
        #expect(trk == [
            "/Users/me/workspace/projects/waypoint/.claude/CLAUDE.md",
            "/Users/me/workspace/projects/waypoint/.claude/rules/api/a.md",
            "/Users/me/workspace/projects/waypoint/AGENTS.md",
            "/Users/me/workspace/projects/waypoint/CLAUDE.local.md",
            "/Users/me/workspace/projects/waypoint/CLAUDE.md",
        ])
        #expect(try source(snapshot, "/Users/me/workspace/projects/waypoint/CLAUDE.local.md").kind == .local)
        #expect(try source(snapshot, "/Users/me/workspace/projects/waypoint/CLAUDE.md").entryCount == 2)
        #expect(try source(snapshot, "/Users/me/workspace/projects/waypoint/AGENTS.md").tool == .codex)

        // 상위 폴더: 홈까지 올라가며 찾고, 두 프로젝트 모두에 걸린다.
        #expect(snapshot.ancestors == ["/Users/me/workspace/projects", "/Users/me/workspace", "/Users/me"])
        let upper = try source(snapshot, "/Users/me/workspace/CLAUDE.md")
        #expect(upper.scope == .ancestor("/Users/me/workspace") && upper.appliesTo == ["CHM", "TRK"])
        // 저장소 밖 AGENTS.md는 Codex가 읽지 않는다.
        #expect(try source(snapshot, "/Users/me/workspace/AGENTS.md").tool == .claude)
    }

    @Test func memoryFoldersArePaired() throws {
        let snapshot = collector(machine()).collect(projects: projects)
        let byName = Dictionary(uniqueKeysWithValues: snapshot.memoryFolders.map { ($0.name, $0) })
        #expect(byName["-Users-me-workspace-projects-waypoint"]?.match == .projects(["TRK"]))
        // credit_system → credit-system
        #expect(byName["-Users-me-workspace-projects-credit-system"]?.match == .projects(["CHM"]))
        #expect(byName["-Users-me-workspace"]?.match == .ancestor("/Users/me/workspace"))
        #expect(byName["-Users-me-workspace-job"]?.match == .other(path: "/Users/me/workspace/job", onDisk: true))
        #expect(byName["-Users-me-workspace-old-app"]?.match == .other(path: "/Users/me/workspace/old/app", onDisk: false))
        // 빈 기억 폴더는 뺀다.
        #expect(byName["-Users-me-workspace-projects-empty"] == nil)
        #expect(snapshot.otherFolders == ["-Users-me-workspace-job", "-Users-me-workspace-old-app"])

        let index = try source(snapshot, "/Users/me/.claude/projects/-Users-me-workspace/memory/MEMORY.md")
        #expect(index.kind == .memoryIndex && index.entryCount == 2)
        #expect(index.scope == .ancestor("/Users/me/workspace") && index.appliesTo == ["CHM", "TRK"])
        let trkMemory = snapshot.sources(in: .project("TRK")).filter(\.isMemory)
        #expect(trkMemory.count == 2 && trkMemory.allSatisfy { $0.memoryFolder == "-Users-me-workspace-projects-waypoint" })
        // 대화 기록은 출처가 아니다.
        #expect(!snapshot.sources.contains { $0.path.hasSuffix(".jsonl") })
    }

    @Test func applyingIncludesGlobalAncestorAndMemory() {
        let snapshot = collector(machine()).collect(projects: projects)
        let chm = snapshot.applying(to: "CHM").map(\.path)
        #expect(chm.contains("/Users/me/.claude/CLAUDE.md"))
        #expect(chm.contains("/Users/me/workspace/CLAUDE.md"))
        #expect(chm.contains("/Users/me/workspace/projects/credit_system/AGENTS.md"))
        #expect(chm.contains("/Users/me/.claude/projects/-Users-me-workspace-projects-credit-system/memory/MEMORY.md"))
        #expect(!chm.contains("/Users/me/workspace/projects/waypoint/CLAUDE.md"))
        #expect(!chm.contains { $0.contains("-Users-me-workspace-job") })
    }

    @Test func worktreeSharesMainRepositoryMemory() {
        let fs = FakeGuidanceFileSystem()
        fs.directory("/Users/me/repo/.git/worktrees/feature")
        fs.file("/Users/me/wt/feature/.git", "gitdir: /Users/me/repo/.git/worktrees/feature\n")
        fs.file("/Users/me/.claude/projects/-Users-me-repo/memory/MEMORY.md", "- a\n")
        let snapshot = GuidanceCollector(home: home, fileSystem: fs, codexMemoryCount: { _ in nil })
            .collect(projects: [GuidanceProject(key: "WT", rootPath: "/Users/me/wt/feature")])
        #expect(snapshot.memoryFolders.first?.match == .projects(["WT"]))
    }

    @Test func sameEncodedNameLinksEveryProject() {
        let fs = FakeGuidanceFileSystem()
        fs.directory("/Users/me/a_b").directory("/Users/me/a-b")
        fs.file("/Users/me/.claude/projects/-Users-me-a-b/memory/MEMORY.md", "- a\n")
        let snapshot = GuidanceCollector(home: home, fileSystem: fs, codexMemoryCount: { _ in nil })
            .collect(projects: [GuidanceProject(key: "AB", rootPath: "/Users/me/a_b"),
                                GuidanceProject(key: "AD", rootPath: "/Users/me/a-b")])
        #expect(snapshot.memoryFolders.first?.match == .projects(["AB", "AD"]))
        #expect(snapshot.sources.first?.appliesTo == ["AB", "AD"])
    }

    @Test func symlinkedProjectMatchesBothSpellings() {
        let fs = FakeGuidanceFileSystem()
        fs.directory("/Volumes/data/app")
        fs.link("/Users/me/app", to: "/Volumes/data/app")
        fs.file("/Users/me/.claude/projects/-Users-me-app/memory/MEMORY.md", "- a\n")
        fs.file("/Users/me/.claude/projects/-Volumes-data-app/memory/MEMORY.md", "- b\n")
        let snapshot = GuidanceCollector(home: home, fileSystem: fs, codexMemoryCount: { _ in nil })
            .collect(projects: [GuidanceProject(key: "APP", rootPath: "/Users/me/app")])
        #expect(snapshot.memoryFolders.map(\.match) == [.projects(["APP"]), .projects(["APP"])])
    }

    @Test func collectingOnlyReads() {
        let fs = machine()
        _ = collector(fs).collect(projects: projects)
        let verbs = Set(fs.calls.map { String($0.prefix { $0 != " " }) })
        #expect(verbs.isSubset(of: ["info", "list", "read"]))
        // 기록 파일·로그 DB는 열지 않는다.
        #expect(!fs.calls.contains { $0.hasPrefix("read") && ($0.hasSuffix(".jsonl") || $0.hasSuffix(".sqlite")) })
    }

    @Test func entryCounts() {
        #expect(GuidanceCount.entries(in: Data("- a\n  * b\n본문\n".utf8), kind: .memoryIndex) == 2)
        #expect(GuidanceCount.entries(in: Data("# c\nprefix_rule()\n\n".utf8), kind: .commandRules) == 1)
        #expect(GuidanceCount.entries(in: Data("a\n\n b \n".utf8), kind: .project) == 2)
    }

    @Test func environmentOverridesHomes() {
        let c = GuidanceCollector.current(environment: ["CODEX_HOME": "/opt/codex", "CLAUDE_CONFIG_DIR": ""], home: home)
        #expect(c.codexHome == "/opt/codex")
        #expect(c.claudeHome == "/Users/me/.claude")
    }
}

@Suite struct GuidanceFormatTests {
    func source(_ kind: GuidanceKind, _ path: String, count: Int? = 3, size: Int64 = 2048) -> GuidanceSource {
        GuidanceSource(kind: kind, tool: kind == .commandRules || kind == .codexMemory ? .codex : .claude,
                       path: path, scope: .global, size: size, entryCount: count)
    }

    @Test func counts() {
        #expect(GuidanceFormat.count(source(.memoryIndex, "/m/MEMORY.md")) == "항목 3")
        #expect(GuidanceFormat.count(source(.commandRules, "/c/default.rules", count: 33)) == "규칙 33")
        #expect(GuidanceFormat.count(source(.project, "/p/CLAUDE.md", count: 26)) == "26줄")
        #expect(GuidanceFormat.count(source(.codexMemory, "/c/m.sqlite", count: nil)) == "읽을 수 없음")
    }

    @Test func titles() {
        #expect(GuidanceFormat.title(source(.project, "/Users/me/app/.claude/CLAUDE.md"), base: "/Users/me/app") == ".claude/CLAUDE.md")
        #expect(GuidanceFormat.title(source(.global, "/Users/me/.claude/CLAUDE.md"), home: "/Users/me") == "~/.claude/CLAUDE.md")
        #expect(GuidanceFormat.title(source(.memory, "/Users/me/.claude/projects/x/memory/notes.md")) == "notes.md")
        #expect(GuidanceFormat.title(source(.codexMemory, "/Users/me/.codex/memories_1.sqlite")) == "Codex 기억")
    }

    @Test func factsAndFolders() {
        #expect(GuidanceFormat.facts(source(.memoryIndex, "/m/MEMORY.md")) == "Claude · 기억 목록 · 항목 3 · 2.0KB")
        #expect(GuidanceFormat.facts(source(.codexMemory, "/c/m.sqlite", count: nil)) == "Codex · Codex 기억 · 읽을 수 없음")
        #expect(GuidanceFormat.size(900) == "900B")
        #expect(GuidanceFormat.size(45_056) == "44KB")
        #expect(GuidanceFormat.otherFolderTitle(path: "/Users/me/old/app", onDisk: false, home: "/Users/me") == "~/old/app · 없는 폴더")
        #expect(GuidanceFormat.otherFolderTitle(path: "/Users/me/job", onDisk: true, home: "/Users/me") == "~/job")
    }
}

@Suite struct GuidanceTextTests {
    @Test func headerIsSplitOff() {
        let (header, body) = GuidanceText.splitHeader("---\nname: a\ntype: user\n---\n\n본문\n")
        #expect(header == "name: a\ntype: user")
        #expect(body == "본문")
    }

    @Test func noHeaderKeepsContent() {
        #expect(GuidanceText.splitHeader("# 제목\n---\n").header == nil)
        #expect(GuidanceText.splitHeader("---\n열기만\n").body == "---\n열기만\n")
    }
}
