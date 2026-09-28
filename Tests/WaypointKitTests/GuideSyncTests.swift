import Foundation
import Testing
@testable import WaypointKit

@Suite struct GuideSyncDecisionTests {
    let stored = "원문\n"
    var storedHash: String { GuideFile.hash(stored) }

    func decide(draft: String? = nil, wasMissing: Bool = false, disk: GuideFile.Disk) -> GuideSync.Decision {
        GuideSync.decide(storedContent: stored, storedHash: storedHash, draft: draft, wasMissing: wasMissing, disk: disk)
    }

    func present(_ s: String) -> GuideFile.Disk { .present(content: s, hash: GuideFile.hash(s)) }

    @Test func sameHashDoesNothing() {
        #expect(decide(disk: present(stored)) == .none)
        // 저장 안 한 편집이 있어도 파일이 그대로면 아무것도 안 한다(앱 자신의 쓰기 포함)
        #expect(decide(draft: "편집중", disk: present(stored)) == .none)
    }

    @Test func changedWithoutDraftApplies() {
        #expect(decide(disk: present("로컬 수정")) == .applyLocal("로컬 수정"))
    }

    @Test func changedWithDraftConflicts() {
        #expect(decide(draft: "앱 수정", disk: present("로컬 수정")) == .conflict("로컬 수정"))
    }

    @Test func draftEqualToStoredIsNotAConflict() {
        #expect(decide(draft: stored, disk: present("로컬 수정")) == .applyLocal("로컬 수정"))
    }

    @Test func draftEqualToDiskIsNotAConflict() {
        // 양쪽이 같은 내용으로 고쳤다
        #expect(decide(draft: "같은 수정", disk: present("같은 수정")) == .applyLocal("같은 수정"))
    }

    @Test func missingMarksOnce() {
        #expect(decide(disk: .missing) == .markMissing)
        #expect(decide(wasMissing: true, disk: .missing) == .none)
        #expect(decide(draft: "편집중", disk: .missing) == .markMissing)
    }

    @Test func reappearUnchangedClearsFlag() {
        #expect(decide(wasMissing: true, disk: present(stored)) == .clearMissing)
    }

    @Test func reappearChangedApplies() {
        #expect(decide(wasMissing: true, disk: present("새 내용")) == .applyLocal("새 내용"))
        #expect(decide(draft: "편집중", wasMissing: true, disk: present("새 내용")) == .conflict("새 내용"))
    }

    @Test func saveCheck() {
        #expect(GuideSync.checkBeforeSave(storedHash: storedHash, disk: present(stored)) == .write)
        #expect(GuideSync.checkBeforeSave(storedHash: storedHash, disk: .missing) == .write)
        #expect(GuideSync.checkBeforeSave(storedHash: storedHash, disk: present("바뀜")) == .conflict("바뀜"))
    }

    @Test func hashIsSHA256Hex() {
        #expect(GuideFile.hash("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}

/// 임시 폴더. 끝나면 지운다.
final class TempDir {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ rel: String, _ content: String) throws -> URL {
        let file = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file)
        return file
    }

    func read(_ rel: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(rel), encoding: .utf8)
    }
}

@Suite struct GuideFileTests {
    @Test func atomicWriteReplacesAndLeavesNoTemp() throws {
        let dir = try TempDir()
        let file = try dir.write("GUIDE.md", "옛 내용")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try GuideFile.writeAtomically("새 내용\n", to: file)
        #expect(try dir.read("GUIDE.md") == "새 내용\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.url.path) == ["GUIDE.md"])
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func atomicWriteCreatesMissingFile() throws {
        let dir = try TempDir()
        let file = dir.url.appendingPathComponent("NEW.md")
        try GuideFile.writeAtomically("처음", to: file)
        #expect(try GuideFile.read(file) == .present(content: "처음", hash: GuideFile.hash("처음")))
    }

    @Test func readMissing() throws {
        let dir = try TempDir()
        #expect(try GuideFile.read(dir.url.appendingPathComponent("none.md")) == .missing)
    }
}

@Suite struct GuidePathsTests {
    @Test func relativePathInsideRoot() throws {
        let dir = try TempDir()
        let root = dir.url
        #expect(GuidePaths.relativePath(of: root.appendingPathComponent("docs/A.md"), under: root) == "docs/A.md")
        #expect(GuidePaths.relativePath(of: root.appendingPathComponent("notes.TXT"), under: root) == "notes.TXT")
    }

    @Test func rejectsOutsideAndOtherTypes() throws {
        let dir = try TempDir()
        let root = dir.url.appendingPathComponent("proj", isDirectory: true)
        #expect(GuidePaths.relativePath(of: dir.url.appendingPathComponent("other.md"), under: root) == nil)
        #expect(GuidePaths.relativePath(of: dir.url.appendingPathComponent("proj2/a.md"), under: root) == nil)
        #expect(GuidePaths.relativePath(of: root.appendingPathComponent("a.swift"), under: root) == nil)
        #expect(GuidePaths.relativePath(of: root.appendingPathComponent("../other.md"), under: root) == nil)
    }

    @Test func symlinkedRoot() throws {
        let dir = try TempDir()
        try dir.write("real/CLAUDE.md", "x")
        let link = dir.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.url.appendingPathComponent("real"))
        // 링크로 된 루트 아래를 실제 경로로 골라도, 실제 루트 아래를 링크 경로로 골라도 같다
        #expect(GuidePaths.relativePath(of: dir.url.appendingPathComponent("real/CLAUDE.md"), under: link) == "CLAUDE.md")
        #expect(GuidePaths.relativePath(of: link.appendingPathComponent("CLAUDE.md"), under: dir.url.appendingPathComponent("real")) == "CLAUDE.md")
    }

    @Test func candidates() throws {
        let dir = try TempDir()
        try dir.write("README.md", "")
        try dir.write("CLAUDE.md", "")
        try dir.write("notes.txt", "")
        try dir.write(".hidden.md", "")
        try dir.write("docs/SPEC.md", "")
        try dir.write("docs/deep/X.md", "")
        try dir.write(".claude/CLAUDE.md", "")
        try dir.write(".claude/other.md", "")
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("folder.md"), withIntermediateDirectories: true)
        #expect(GuidePaths.candidates(in: dir.url, excluding: []) == ["CLAUDE.md", "README.md", "docs/SPEC.md", ".claude/CLAUDE.md"])
        #expect(GuidePaths.candidates(in: dir.url, excluding: ["CLAUDE.md", "docs/SPEC.md"]) == ["README.md", ".claude/CLAUDE.md"])
    }
}

@Suite struct LineDiffTests {
    @Test func identical() {
        #expect(LineDiff.diff("a\nb\n", "a\nb\n") == [.init(.same, "a"), .init(.same, "b")])
    }

    @Test func addedAndRemoved() {
        let d = LineDiff.diff(["a", "b", "c", "d"], ["a", "x", "c", "d", "e"])
        #expect(d == [.init(.same, "a"), .init(.removed, "b"), .init(.added, "x"), .init(.same, "c"), .init(.same, "d"), .init(.added, "e")])
    }

    @Test func emptySides() {
        #expect(LineDiff.diff("", "a\n") == [.init(.added, "a")])
        #expect(LineDiff.diff("a", "") == [.init(.removed, "a")])
        #expect(LineDiff.diff("", "").isEmpty)
    }

    @Test func middleInsertKeepsCommonLines() {
        let d = LineDiff.diff(["# 제목", "본문", "끝"], ["# 제목", "새 줄", "본문", "끝"])
        #expect(d.filter { $0.kind == .same }.map(\.text) == ["# 제목", "본문", "끝"])
        #expect(d.filter { $0.kind == .added }.map(\.text) == ["새 줄"])
        #expect(!d.contains { $0.kind == .removed })
    }

    @Test func overLimitFallsBack() {
        let old = (0..<2100).map { "o\($0)" }
        let new = (0..<2100).map { "n\($0)" }
        let d = LineDiff.diff(["top"] + old, ["top"] + new)
        #expect(d.first == .init(.same, "top"))
        #expect(d.filter { $0.kind == .removed }.count == 2100)
        #expect(d.filter { $0.kind == .added }.count == 2100)
    }
}
