import Foundation
import SwiftData

/// 지침 출처를 항목 화면에서 고칠 수 있는지와 어디로 쓰는지.
/// 등록 프로젝트 폴더 안의 지침 파일은 지침 문서(`GuideDoc`)로, 전역·상위 폴더·기억·`.claude/rules`·Codex 규칙은
/// 파일 그대로(`GuidanceFileWrite`: 백업·충돌 확인) 쓴다. Codex 기억 DB와 관리 정책 파일은 보기만.
public enum GuideItemTarget {
    /// 보기만
    case readOnly
    /// 지침 문서로 등록하지 않고 파일에 바로 쓴다(이 Mac의 백업만 남는다)
    case file(GuidanceSource)
    /// 이미 지침 문서로 등록된 파일
    case registered(GuideDoc)
    /// 프로젝트 안 지침 파일이지만 아직 등록 전. 처음 고칠 때 등록한다.
    case registerable(Project, relPath: String)

    /// 등록 전에 고칠 수 있는 출처 종류: 프로젝트 `CLAUDE.md`·`.claude/CLAUDE.md`·`AGENTS.md`(·override)·`CLAUDE.local.md`
    public static let writableKinds: Set<GuidanceKind> = [.project, .local]

    public static func resolve(_ source: GuidanceSource, projects: [Project],
                               fileSystem: GuidanceFileSystem = DiskGuidanceFileSystem()) -> GuideItemTarget {
        // 프로젝트 밖 파일은 파일 그대로. 단 이미 지침 문서로 등록된 파일이면 그 문서로(아래).
        let external: GuideItemTarget = GuidanceFileWrite.isWritable(kind: source.kind, path: source.path)
            ? .file(source) : .readOnly
        guard case .project(let key) = source.scope,
              let project = projects.first(where: { $0.key == key }),
              let root = GuidePaths.rootURL(project.rootPath)
        else { return external }
        let path = fileSystem.resolve(source.path)
        if let doc = (project.guideDocs ?? []).first(where: { doc in
            GuideLibrary.fileURL(of: doc).map { fileSystem.resolve($0.path) } == path
        }) {
            return .registered(doc)
        }
        guard !GuidanceFileWrite.writableKinds.contains(source.kind) else { return external }
        guard writableKinds.contains(source.kind),
              let relPath = GuidePaths.relativePath(of: URL(fileURLWithPath: path), under: root)
        else { return .readOnly }
        return .registerable(project, relPath: relPath)
    }

    public var isWritable: Bool {
        if case .readOnly = self { false } else { true }
    }

    /// 등록 문서. 등록 전이면 지금 등록한다(M4 등록: `GuideVersion(local)`, `guide.synced`).
    public func document(at date: Date, context: ModelContext) throws -> GuideDoc? {
        switch self {
        case .readOnly, .file: nil
        case .registered(let doc): doc
        case .registerable(let project, let relPath):
            try GuideLibrary.register(relPath, in: project, at: date, context: context)
        }
    }
}
