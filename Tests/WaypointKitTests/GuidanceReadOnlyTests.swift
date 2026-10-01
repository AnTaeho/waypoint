import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import WaypointKit

/// 실제 디스크(임시 폴더)에서 수집·DB 읽기가 아무것도 쓰지 않는지.
@Suite struct GuidanceReadOnlyTests {

    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("guidance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    /// 폴더 아래 모든 파일의 경로 → (크기, 수정 시각, 해시)
    func fingerprint(_ root: URL) -> [String: String] {
        var result: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            let data = (values?.isDirectory == true) ? Data() : ((try? Data(contentsOf: url)) ?? Data())
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            result[url.path] = "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0) \(hash)"
        }
        return result
    }

    func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// WAL 모드 DB를 만들고 행을 넣는다. 돌려준 연결을 닫기 전까지 `-wal`이 남는다.
    func makeDatabase(_ path: String, rows: Int, schema: String? = nil) throws -> OpaquePointer {
        var db: OpaquePointer?
        try #require(sqlite3_open(path, &db) == SQLITE_OK)
        let create = schema ?? """
            CREATE TABLE stage1_outputs (thread_id TEXT PRIMARY KEY, source_updated_at INTEGER NOT NULL,
            raw_memory TEXT NOT NULL, rollout_summary TEXT NOT NULL, generated_at INTEGER NOT NULL)
            """
        try #require(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; \(create);", nil, nil, nil) == SQLITE_OK)
        for i in 0..<rows {
            let sql = "INSERT INTO stage1_outputs VALUES ('t\(i)', \(1_790_000_000 + i), '기억 \(i)\n둘째 줄', 's', 0)"
            try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        return try #require(db)
    }

    @Test func collectingTouchesNothing() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        try write("# 전역\n", home.appendingPathComponent(".claude/CLAUDE.md"))
        try write("- a\n", home.appendingPathComponent(".claude/projects/x/memory/MEMORY.md"))
        try write("CLAUDE\n", home.appendingPathComponent("work/CLAUDE.md"))
        try write("p\n", home.appendingPathComponent("work/app/CLAUDE.md"))
        try write("prefix_rule()\n", home.appendingPathComponent(".codex/rules/default.rules"))
        let writer = try makeDatabase(home.appendingPathComponent(".codex/memories_1.sqlite").path, rows: 2)
        defer { sqlite3_close(writer) }

        let before = fingerprint(root)
        let snapshot = GuidanceCollector(home: home.path)
            .collect(projects: [GuidanceProject(key: "APP", rootPath: home.appendingPathComponent("work/app").path)])
        #expect(snapshot.sources.contains { $0.kind == .codexMemory && $0.entryCount == 2 })
        #expect(snapshot.sources.count == 6)
        #expect(withoutSharedMemory(fingerprint(root)) == withoutSharedMemory(before))
    }

    /// WAL 읽기는 SQLite가 `-shm`(공유 메모리 색인)의 읽기 표시를 고친다. 내용(본문·WAL)과 파일 목록만 비교한다.
    func withoutSharedMemory(_ print: [String: String]) -> [String: String] {
        print.filter { !$0.key.hasSuffix("-shm") }.merging(
            print.filter { $0.key.hasSuffix("-shm") }.mapValues { _ in "shm" }
        ) { a, _ in a }
    }

    @Test func readsRowsStillInWriteAheadLog() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("memories_1.sqlite").path
        let writer = try makeDatabase(path, rows: 3)
        defer { sqlite3_close(writer) }
        #expect(FileManager.default.fileExists(atPath: path + "-wal"))
        let before = fingerprint(root)

        guard case .entries(let total, let recent) = CodexMemoryStore.read(path: path, limit: 2) else {
            Issue.record("읽지 못함")
            return
        }
        #expect(total == 3)
        #expect(recent.map(\.threadID) == ["t2", "t1"])
        #expect(recent[0].summary == "기억 2 둘째 줄")
        #expect(recent[0].updatedAt == Date(timeIntervalSince1970: 1_790_000_002))
        // 본문·WAL은 그대로, 새 파일(-journal 등)도 없다.
        let after = fingerprint(root)
        #expect(Set(after.keys) == Set(before.keys))
        #expect(after[path] == before[path] && after[path + "-wal"] == before[path + "-wal"])
    }

    @Test func readsCheckpointedDatabaseWithoutCreatingFiles() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("memories_1.sqlite").path
        sqlite3_close(try makeDatabase(path, rows: 1))
        let before = fingerprint(root)
        #expect(CodexMemoryStore.read(path: path).count == 1)
        #expect(withoutSharedMemory(fingerprint(root)) == withoutSharedMemory(before))
    }

    @Test func otherSchemaIsUnreadable() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("memories_1.sqlite").path
        sqlite3_close(try makeDatabase(path, rows: 0, schema: "CREATE TABLE stage1_outputs (id INTEGER)"))
        #expect(CodexMemoryStore.read(path: path) == .unreadable)
        try write("not a database", root.appendingPathComponent("broken.sqlite"))
        #expect(CodexMemoryStore.read(path: root.appendingPathComponent("broken.sqlite").path) == .unreadable)
        #expect(CodexMemoryStore.read(path: root.appendingPathComponent("none.sqlite").path) == .missing)
    }
}

@Suite struct GuidanceWatchPlanTests {
    let fs = FakeGuidanceFileSystem()

    var plan: GuidanceWatchPlan {
        let collector = GuidanceCollector(home: "/Users/me", fileSystem: fs, codexMemoryCount: { _ in nil })
        return GuidanceWatchPlan(
            collector: collector,
            projects: [GuidanceProject(key: "A", rootPath: "/Users/me/workspace/projects/a"),
                       GuidanceProject(key: "B", rootPath: "/Users/me/workspace/projects/b")],
            ancestors: ["/Users/me/workspace/projects", "/Users/me/workspace", "/Users/me"]
        )
    }

    @Test func rootsSkipHomeAndNestedFolders() {
        #expect(plan.roots == ["/Users/me/.claude", "/Users/me/.codex", "/Users/me/workspace"])
    }

    @Test func busyFilesAreIgnored() {
        let p = plan
        #expect(!p.accepts("/Users/me/.claude/projects/-Users-me-a/0f2c.jsonl"))
        #expect(!p.accepts("/Users/me/.claude/projects/-Users-me-a/0f2c/subagents/x.jsonl"))
        #expect(!p.accepts("/Users/me/.codex/logs_2.sqlite-wal"))
        #expect(!p.accepts("/Users/me/.codex/memories_1.sqlite-shm"))
        #expect(!p.accepts("/Users/me/workspace/projects/a/Sources/App.swift"))
        #expect(!p.accepts("/Users/me/workspace/projects/a/README.md"))
    }

    @Test func sourceChangesAreAccepted() {
        let p = plan
        #expect(p.accepts("/Users/me/.claude/CLAUDE.md"))
        #expect(p.accepts("/Users/me/.claude/projects/-Users-me-a/memory/feedback.md"))
        #expect(p.accepts("/Users/me/.claude/projects/-Users-me-a/memory"))
        #expect(p.accepts("/Users/me/.claude/projects/-Users-me-new"))
        #expect(p.accepts("/Users/me/.claude/rules/style.md"))
        #expect(p.accepts("/Users/me/.codex/rules/default.rules"))
        #expect(p.accepts("/Users/me/.codex/memories_1.sqlite-wal"))
        #expect(p.accepts("/Users/me/workspace/AGENTS.md"))
        #expect(p.accepts("/Users/me/workspace/projects/a/.claude/rules/api.md"))
        #expect(p.accepts("/Users/me/workspace/projects/a/CLAUDE.local.md"))
    }
}
