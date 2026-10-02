import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 항목 고치기·지우기·되돌리기: 실제 임시 파일과 버전 기록.
@Suite struct GuideItemEditTests {
    static let sample = """
    # 규칙

    - 첫째
    - 둘째
      - 둘째 하위 1
      - 둘째 하위 2
    - 셋째

    """

    func setup(_ content: String = sample) throws -> (ModelContainer, ModelContext, TempDir, Project, GuideDoc) {
        let (c, ctx) = try makeContext()
        let dir = try TempDir()
        let p = makeProject(ctx)
        p.rootPath = dir.url.path
        try dir.write("CLAUDE.md", content)
        let doc = try GuideLibrary.register("CLAUDE.md", in: p, at: t0, context: ctx)
        return (c, ctx, dir, p, doc)
    }

    func item(_ content: String, _ id: [Int]) throws -> GuidanceItem {
        try #require(GuidanceDocument.parse(content, format: .markdown).item(id: id))
    }

    @Test func replaceWritesFileAndRecordsVersion() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        let first = try item(doc.content, [1])
        #expect(first.text == "- 첫째")
        let result = try GuideItemEdit.replace(doc, base: doc.content, item: first, with: "- 처음", at: t0 + 60, context: ctx)
        #expect(result == .saved)
        #expect(try dir.read("CLAUDE.md") == Self.sample.replacingOccurrences(of: "- 첫째", with: "- 처음"))
        #expect(GuideLibrary.versions(of: doc).map(\.source) == [.app, .local])
        #expect(doc.draft == nil && doc.conflictContent == nil)
    }

    @Test func deleteWithChildrenThenUndo() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        let second = try item(doc.content, [2])
        #expect(second.children.count == 2)
        let (result, removal) = try GuideItemEdit.delete(doc, base: doc.content, item: second, at: t0 + 60, context: ctx)
        #expect(result == .saved)
        #expect(removal.childCount == 2 && removal.preview == "둘째")
        #expect(GuideItemEdit.summary(removal) == "지움 · 둘째 · 하위 2개 포함")
        #expect(try dir.read("CLAUDE.md") == "# 규칙\n\n- 첫째\n- 셋째\n")

        #expect(try GuideItemEdit.undo(doc, removal, at: t0 + 120, context: ctx) == .saved)
        #expect(try dir.read("CLAUDE.md") == Self.sample)
        // 되돌리기도 새 버전(app)
        #expect(GuideLibrary.versions(of: doc).map(\.source) == [.app, .app, .local])
        #expect(GuideLibrary.versions(of: doc).first?.content == Self.sample)
    }

    @Test func summaryWithoutChildren() throws {
        let removal = GuideItemEdit.Removal(before: "", after: "", preview: "첫째", childCount: 0)
        #expect(GuideItemEdit.summary(removal) == "지움 · 첫째")
        let long = try item("- `swift test`를 **세 번** 돌리고 결과를 원문 그대로 붙인다\n", [0])
        #expect(GuideItemEdit.preview(long) == "swift test를 세 번 돌리고 결과를…")
    }

    @Test func ambiguousDocumentCannotDelete() throws {
        let content = "- 하나\n<div>\n둘\n</div>\n"
        let document = GuidanceDocument.parse(content, format: .markdown)
        #expect(document.isAmbiguous)
        #expect(!GuideItemEdit.canDelete(document))
        #expect(GuideItemEdit.canDelete(GuidanceDocument.parse(Self.sample, format: .markdown)))
        let (_c, ctx, dir, _, doc) = try setup(content); _ = _c
        let whole = try item(content, [0])
        #expect(throws: GuideItemEdit.Failure.ambiguous) {
            try GuideItemEdit.delete(doc, base: content, item: whole, at: t0 + 1, context: ctx)
        }
        #expect(try dir.read("CLAUDE.md") == content)
        // 고치기(문서 전체)는 된다
        #expect(try GuideItemEdit.replace(doc, base: content, item: whole, with: "- 하나만", at: t0 + 2, context: ctx) == .saved)
        #expect(try dir.read("CLAUDE.md") == "- 하나만\n")
    }

    @Test func staleItemIsRejected() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        var first = try item(doc.content, [1])
        first.text = "- 다른 글"
        #expect(throws: GuideItemEdit.Failure.staleItem) {
            try GuideItemEdit.replace(doc, base: doc.content, item: first, with: "- 처음", at: t0 + 1, context: ctx)
        }
        #expect(try dir.read("CLAUDE.md") == Self.sample)
    }

    /// 편집 상자를 연 사이 로컬 변경이 앱에 반영됐으면 쓰지 않고 비교 화면으로.
    @Test func externalChangeAppliedWhileEditingConflicts() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        let base = doc.content
        let first = try item(base, [1])
        let local = Self.sample + "- 로컬에서 더함\n"
        try dir.write("CLAUDE.md", local)
        #expect(GuideLibrary.check(doc, at: t0 + 5, context: ctx) == .applyLocal(local))
        let result = try GuideItemEdit.replace(doc, base: base, item: first, with: "- 처음", at: t0 + 10, context: ctx)
        #expect(result == .conflict)
        #expect(try dir.read("CLAUDE.md") == local)
        #expect(doc.conflictContent == local)
        #expect(doc.draft == base.replacingOccurrences(of: "- 첫째", with: "- 처음"))
    }

    /// 상자 내용이 draft로 남아 있으면 감시가 로컬 변경을 충돌로 판정한다(M4 규칙).
    @Test func draftWhileEditingTurnsLocalChangeIntoConflict() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        let first = try item(doc.content, [1])
        GuideItemEdit.setDraft(doc, base: doc.content, item: first, text: "- 처음")
        #expect(doc.draft == Self.sample.replacingOccurrences(of: "- 첫째", with: "- 처음"))
        GuideItemEdit.setDraft(doc, base: doc.content, item: first, text: "- 첫째")
        #expect(doc.draft == nil)
        GuideItemEdit.setDraft(doc, base: doc.content, item: first, text: "- 처음")
        try dir.write("CLAUDE.md", "로컬\n")
        #expect(GuideLibrary.check(doc, at: t0 + 5, context: ctx) == .conflict("로컬\n"))
        #expect(try dir.read("CLAUDE.md") == "로컬\n")
    }

    /// 감시가 아직 못 본 디스크 변경은 저장 경로가 해시로 잡는다.
    @Test func diskChangedBeforeCheckConflicts() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        let third = try item(doc.content, [3])
        try dir.write("CLAUDE.md", "로컬\n")
        let (result, _) = try GuideItemEdit.delete(doc, base: doc.content, item: third, at: t0 + 5, context: ctx)
        #expect(result == .conflict)
        #expect(try dir.read("CLAUDE.md") == "로컬\n")
        #expect(doc.conflictContent == "로컬\n" && doc.draft == "# 규칙\n\n- 첫째\n- 둘째\n  - 둘째 하위 1\n  - 둘째 하위 2\n")
    }

    /// 지운 뒤 로컬 변경이 반영됐으면 되돌리기가 덮어쓰지 않는다.
    @Test func undoAfterLocalChangeConflicts() throws {
        let (_c, ctx, dir, _, doc) = try setup(); _ = _c
        let (_, removal) = try GuideItemEdit.delete(doc, base: doc.content, item: try item(doc.content, [1]),
                                                    at: t0 + 5, context: ctx)
        try dir.write("CLAUDE.md", "로컬\n")
        #expect(GuideLibrary.check(doc, at: t0 + 6, context: ctx) == .applyLocal("로컬\n"))
        #expect(try GuideItemEdit.undo(doc, removal, at: t0 + 7, context: ctx) == .conflict)
        #expect(try dir.read("CLAUDE.md") == "로컬\n")
        #expect(doc.draft == Self.sample && doc.conflictContent == "로컬\n")
    }
}

/// 항목 화면의 쓰기 대상: 프로젝트 안 파일만, 처음 고치면 등록.
@Suite struct GuideItemTargetTests {
    let fs = DiskGuidanceFileSystem()

    func source(_ path: String, kind: GuidanceKind, scope: GuidanceScope) -> GuidanceSource {
        GuidanceSource(kind: kind, tool: .claude, path: fs.resolve(path), scope: scope)
    }

    @Test func unregisteredProjectFileRegistersOnFirstEdit() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let dir = try TempDir()
        let p = makeProject(ctx)
        p.rootPath = dir.url.path
        let file = try dir.write(".claude/CLAUDE.md", "- 하나\n- 둘\n")
        let target = GuideItemTarget.resolve(source(file.path, kind: .project, scope: .project(p.key)), projects: [p])
        guard case .registerable(_, let relPath) = target else { Issue.record("등록 대상 아님: \(target)"); return }
        #expect(relPath == ".claude/CLAUDE.md")

        let base = try #require(try GuideFile.read(file).content)
        let doc = try #require(try target.document(at: t0, context: ctx))
        let second = try #require(GuidanceDocument.parse(base, format: .markdown).item(id: [1]))
        #expect(try GuideItemEdit.replace(doc, base: base, item: second, with: "- 둘째", at: t0 + 1, context: ctx) == .saved)
        #expect(try dir.read(".claude/CLAUDE.md") == "- 하나\n- 둘째\n")
        #expect(GuideLibrary.versions(of: doc).map(\.source) == [.app, .local])

        // 등록 뒤에는 같은 문서를 찾는다
        let again = GuideItemTarget.resolve(source(file.path, kind: .project, scope: .project(p.key)), projects: [p])
        guard case .registered(let found) = again else { Issue.record("등록 문서 아님"); return }
        #expect(found === doc)
    }

    /// 전역·상위 폴더·기억·색인·rules·Codex 규칙은 파일 그대로 쓰는 대상(TRK-41). 등록 문서는 만들지 않는다.
    @Test func filesOutsideProjectWriteDirectly() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let dir = try TempDir()
        let outside = try TempDir()
        let p = makeProject(ctx)
        p.rootPath = dir.url.path
        let global = try outside.write("CLAUDE.md", "- 전역\n")
        let memory = try outside.write("memory/a.md", "기억\n")
        let index = try outside.write("memory/MEMORY.md", "- [a](a.md)\n")
        let rules = try outside.write("rules/default.rules", "prefix_rule(pattern=[\"ls\"], decision=\"allow\")\n")
        let inside = try dir.write(".claude/rules/a.md", "- 규칙\n")
        let cases: [GuidanceSource] = [
            source(global.path, kind: .global, scope: .global),
            source(global.path, kind: .ancestor, scope: .ancestor(outside.url.path)),
            source(memory.path, kind: .memory, scope: .project(p.key)),
            source(index.path, kind: .memoryIndex, scope: .project(p.key)),
            source(rules.path, kind: .commandRules, scope: .global),
            source(inside.path, kind: .rule, scope: .project(p.key)),
        ]
        for source in cases {
            let target = GuideItemTarget.resolve(source, projects: [p])
            guard case .file(let found) = target else { Issue.record("파일 대상 아님: \(source.kind)"); continue }
            #expect(found.path == source.path)
            #expect(try target.document(at: t0, context: ctx) == nil)
        }
        #expect((p.guideDocs ?? []).isEmpty)
    }

    @Test func readOnlySources() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let dir = try TempDir()
        let outside = try TempDir()
        let p = makeProject(ctx)
        p.rootPath = dir.url.path
        let global = try outside.write("CLAUDE.md", "- 전역\n")
        let db = try outside.write(CodexMemoryStore.fileName, "")
        let cases: [GuidanceSource] = [
            // 프로젝트 묶음이어도 폴더 밖 경로면 쓰지 않는다
            source(global.path, kind: .project, scope: .project(p.key)),
            // 모르는 프로젝트
            source(global.path, kind: .project, scope: .project("NONE")),
            // Codex 기억 DB
            GuidanceSource(kind: .codexMemory, tool: .codex, path: db.path, scope: .global),
            // 관리 정책 파일
            source("/Library/Application Support/ClaudeCode/CLAUDE.md", kind: .global, scope: .global),
        ]
        for source in cases {
            let target = GuideItemTarget.resolve(source, projects: [p])
            #expect(!target.isWritable, "\(source.kind) \(source.scope)")
            #expect(try target.document(at: t0, context: ctx) == nil)
        }
        #expect((p.guideDocs ?? []).isEmpty)
    }
}
