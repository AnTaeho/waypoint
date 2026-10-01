import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct GuideLibraryTests {
    func setup() throws -> (ModelContainer, ModelContext, TempDir, Project) {
        let (c, ctx) = try makeContext()
        let dir = try TempDir()
        let p = makeProject(ctx)
        p.rootPath = dir.url.path
        return (c, ctx, dir, p)
    }

    func guideEvents(_ p: Project) -> [[String: EventValue]] {
        (p.events ?? []).filter { $0.type == .guideSynced }.sorted { $0.at < $1.at }.map(\.payloadValues)
    }

    @Test func registerReadsFileAndRecords() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "# 지침\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        #expect(doc.content == "# 지침\n")
        #expect(doc.contentHash == GuideFile.hash("# 지침\n"))
        #expect(doc.versions?.map(\.source) == [.local])
        #expect(guideEvents(p) == [["relPath": "GUIDE.md", "source": "local"]])
        #expect(throws: GuideLibrary.Failure.alreadyRegistered) {
            try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        }
        #expect(throws: GuideLibrary.Failure.fileMissing) {
            try GuideLibrary.register("NONE.md", in: p, at: t0, context: ctx)
        }
    }

    @Test func saveWritesFileAndIgnoresOwnWrite() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "옛\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        doc.draft = "새\n"
        #expect(try GuideLibrary.save(doc, content: "새\n", at: t0 + 60, context: ctx) == .saved)
        #expect(try dir.read("GUIDE.md") == "새\n")
        #expect(doc.content == "새\n" && doc.draft == nil && doc.lastSyncedAt == t0 + 60)
        #expect(GuideLibrary.versions(of: doc).map(\.source) == [.app, .local])
        // 앱이 쓴 파일을 감시가 다시 확인해도 아무것도 안 한다
        #expect(GuideLibrary.check(doc, at: t0 + 61, context: ctx) == .none)
        #expect(guideEvents(p).last == ["relPath": "GUIDE.md", "source": "app"])
    }

    @Test func localChangeApplies() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "옛\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        try dir.write("GUIDE.md", "로컬\n")
        #expect(GuideLibrary.check(doc, at: t0 + 5, context: ctx) == .applyLocal("로컬\n"))
        #expect(doc.content == "로컬\n" && doc.versions?.count == 2)
    }

    @Test func conflictThenKeepLocal() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "옛\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        doc.draft = "앱\n"
        try dir.write("GUIDE.md", "로컬\n")
        #expect(GuideLibrary.check(doc, at: t0 + 5, context: ctx) == .conflict("로컬\n"))
        #expect(doc.conflictContent == "로컬\n" && doc.content == "옛\n" && doc.draft == "앱\n")
        try GuideLibrary.keepLocal(doc, at: t0 + 10, context: ctx)
        #expect(doc.content == "로컬\n" && doc.draft == nil && doc.conflictContent == nil)
        #expect(GuideLibrary.versions(of: doc).first?.source == .local)
        #expect(try dir.read("GUIDE.md") == "로컬\n")
    }

    @Test func conflictThenKeepApp() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "옛\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        try dir.write("GUIDE.md", "로컬\n")
        // 편집하는 사이 파일이 바뀌었으면 저장이 멈춘다
        #expect(try GuideLibrary.save(doc, content: "앱\n", at: t0 + 5, context: ctx) == .conflict)
        #expect(try dir.read("GUIDE.md") == "로컬\n")
        #expect(doc.draft == "앱\n" && doc.conflictContent == "로컬\n")
        try GuideLibrary.keepApp(doc, at: t0 + 10, context: ctx)
        #expect(try dir.read("GUIDE.md") == "앱\n")
        #expect(doc.content == "앱\n" && doc.draft == nil && doc.conflictContent == nil)
        #expect(GuideLibrary.versions(of: doc).first?.source == .app)
    }

    @Test func missingAndReappear() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        let file = try dir.write("GUIDE.md", "옛\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        try FileManager.default.removeItem(at: file)
        #expect(GuideLibrary.check(doc, at: t0 + 1, context: ctx) == .markMissing)
        #expect(doc.isMissing && doc.content == "옛\n")
        try dir.write("GUIDE.md", "옛\n")
        #expect(GuideLibrary.check(doc, at: t0 + 2, context: ctx) == .clearMissing)
        #expect(!doc.isMissing && doc.versions?.count == 1)
        try FileManager.default.removeItem(at: file)
        GuideLibrary.check(doc, at: t0 + 3, context: ctx)
        // 없어진 파일을 앱에서 저장하면 다시 만든다
        #expect(try GuideLibrary.save(doc, content: "옛\n", at: t0 + 4, context: ctx) == .saved)
        #expect(try dir.read("GUIDE.md") == "옛\n" && !doc.isMissing)
    }

    @Test func revertWritesOldVersionAsApp() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "v1\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        _ = try GuideLibrary.save(doc, content: "v2\n", at: t0 + 1, context: ctx)
        let v1 = try #require(GuideLibrary.versions(of: doc).last)
        #expect(try GuideLibrary.revert(doc, to: v1, at: t0 + 2, context: ctx) == .saved)
        #expect(try dir.read("GUIDE.md") == "v1\n")
        #expect(GuideLibrary.versions(of: doc).map(\.source) == [.app, .app, .local])
    }

    @Test func keepsRecentVersionsOnly() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "0\n")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        for i in 1...(GuideLibrary.versionLimit + 5) {
            _ = try GuideLibrary.save(doc, content: "\(i)\n", at: t0 + Double(i), context: ctx)
        }
        let versions = GuideLibrary.versions(of: doc)
        #expect(versions.count == GuideLibrary.versionLimit)
        #expect(versions.first?.content == "\(GuideLibrary.versionLimit + 5)\n")
        #expect(try ctx.fetchCount(FetchDescriptor<GuideVersion>()) == GuideLibrary.versionLimit)
    }

    @Test func unregisterKeepsFile() throws {
        let (_c, ctx, dir, p) = try setup(); _ = _c
        try dir.write("GUIDE.md", "x")
        let doc = try GuideLibrary.register("GUIDE.md", in: p, at: t0, context: ctx)
        try GuideLibrary.unregister(doc, context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<GuideDoc>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<GuideVersion>()) == 0)
        #expect(try dir.read("GUIDE.md") == "x")
    }
}

#if os(macOS)
@Suite struct GuideWatcherTests {
    /// 실제 FSEvents: 임시 폴더에 쓰기와 원자적 교체를 하면 그 폴더가 콜백으로 온다.
    @Test func reportsWritesInWatchedDirectory() async throws {
        let dir = try TempDir()
        // FSEvents는 /private/var/… 실제 경로로 알려 준다
        let real = try #require(realpath(dir.url.path, nil).map { p in defer { free(p) }; return String(cString: p) })
        let received = Received()
        let watcher = GuideWatcher(debounce: 0.2) { dirs in received.add(dirs) }
        watcher.watch([real])
        try await Task.sleep(for: .milliseconds(500))

        received.reset()
        try dir.write("GUIDE.md", "한 번")
        #expect(await received.wait(for: real, timeout: 10))

        received.reset()
        try GuideFile.writeAtomically("두 번", to: dir.url.appendingPathComponent("GUIDE.md"))
        #expect(await received.wait(for: real, timeout: 10))
        watcher.stop()
    }

    /// 거르는 규칙: 쉬지 않고 쓰이는 파일은 넘기지 않고 디바운스도 미루지 않는다(지침 출처 감시).
    @Test func filteredPathsDoNotDelayFlush() async throws {
        let dir = try TempDir()
        let real = try #require(realpath(dir.url.path, nil).map { p in defer { free(p) }; return String(cString: p) })
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("busy"), withIntermediateDirectories: true)
        let received = Received()
        let watcher = GuideWatcher(debounce: 0.3, accept: { !$0.hasSuffix(".jsonl") }) { dirs in received.add(dirs) }
        watcher.watch([real])
        try await Task.sleep(for: .milliseconds(500))
        received.reset()

        // 대화 기록처럼 0.1초마다 쓰이는 파일이 있어도 CLAUDE.md 변경은 넘어온다.
        let log = dir.url.appendingPathComponent("busy/log.jsonl")
        let busy = Task { [log] in
            for i in 0..<60 {
                try? Data("\(i)\n".utf8).write(to: log)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        try dir.write("CLAUDE.md", "지침")
        #expect(await received.wait(for: real, timeout: 3))
        busy.cancel()
        #expect(!received.contains(real + "/busy"))
        watcher.stop()
    }

    final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var dirs: Set<String> = []

        func add(_ d: Set<String>) { lock.withLock { dirs.formUnion(d) } }
        func reset() { lock.withLock { dirs = [] } }
        func contains(_ dir: String) -> Bool { lock.withLock { dirs.contains(dir) } }

        /// `dir`이 들어올 때까지 기다린다.
        func wait(for dir: String, timeout: TimeInterval) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if lock.withLock({ dirs.contains(dir) }) { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }
    }
}
#endif
