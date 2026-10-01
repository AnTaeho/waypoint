import Foundation
import SwiftData

/// 프로젝트 등록·보관·삭제. 규칙 검사와 저장을 한곳에서 해서 화면과 도구가 같은 규칙을 쓴다.
public enum ProjectRegistry {

    public enum Failure: Error, Equatable {
        case emptyName
        case key(ProjectKey.Problem)
        /// 같은 폴더를 쓰는 프로젝트가 있다(보관 포함). 그 키.
        case folderTaken(String)
        case folderMissing
        /// 지침 파일을 읽지 못했다
        case guideMissing(String)
    }

    /// 보관된 것까지 포함한 모든 키(대문자).
    public static func takenKeys(in context: ModelContext) -> Set<String> {
        Set(allProjects(context).map { $0.key.uppercased() })
    }

    /// 정확히 같은 폴더(정규화 비교)를 쓰는 프로젝트. 보관 포함.
    public static func project(atRoot path: String, in context: ModelContext, home: String = NSHomeDirectory()) -> Project? {
        let target = ProjectMatcher.normalize(path, home: home)
        return allProjects(context).first { !$0.rootPath.isEmpty && ProjectMatcher.normalize($0.rootPath, home: home) == target }
    }

    /// 확인한 초안으로 등록한다. 초안에는 고른 지침 파일·카드만 들어 있다.
    /// 한 번에 저장한다: 프로젝트 → 지침 문서(버전 local, `guide.synced`) → 카드(origin claude, `card.created`).
    /// 실패하면 아무것도 남기지 않는다(저장 안 된 변경을 되돌린다).
    @discardableResult
    public static func register(
        _ draft: ProjectDraft, at date: Date, context: ModelContext,
        home: String = NSHomeDirectory(), fileManager: FileManager = .default
    ) throws -> Project {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.emptyName }
        let key = ProjectKey.normalize(draft.key)
        if let problem = ProjectKey.problem(key, taken: takenKeys(in: context)) { throw Failure.key(problem) }
        let root = ProjectMatcher.normalize(draft.rootPath, home: home)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { throw Failure.folderMissing }
        if let existing = project(atRoot: root, in: context, home: home) { throw Failure.folderTaken(existing.key) }

        let project = Project(
            key: key, name: name,
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            rootPath: root,
            stack: cleanStack(draft.stack),
            createdAt: date
        )
        context.insert(project)
        do {
            for relPath in draft.guideFiles {
                do {
                    try GuideLibrary.add(relPath, to: project, at: date, context: context)
                } catch {
                    throw Failure.guideMissing(relPath)
                }
            }
            for seed in draft.seedCards {
                let title = seed.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let card = project.makeCard(
                    in: context, title: title, kind: seed.kind, status: seed.status,
                    body: seed.body, origin: draft.provider.cardOrigin, at: date
                )
                Event.record(.cardCreated, in: context, project: project, card: card, at: date,
                             payload: ["origin": .string(draft.provider.cardOrigin.rawValue), "status": .string(seed.status.rawValue)])
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return project
    }

    /// 스택 칩: 앞뒤 공백을 떼고 빈 것·중복(대소문자 무시)을 뺀다.
    public static func cleanStack(_ stack: [String]) -> [String] {
        var seen = Set<String>()
        return stack
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: - 정리

    /// 보관: 사이드바·대시보드에서 숨기고 그 폴더의 훅을 받지 않는다. 카드·기록은 그대로.
    public static func archive(_ project: Project, at date: Date, context: ModelContext) throws {
        guard project.archivedAt == nil else { return }
        project.archivedAt = date
        try context.save()
    }

    public static func unarchive(_ project: Project, context: ModelContext) throws {
        guard project.archivedAt != nil else { return }
        project.archivedAt = nil
        try context.save()
    }

    /// 삭제: 카드·세션·기록·지침 문서(버전 포함)를 함께 지운다. 로컬 파일은 건드리지 않는다.
    public static func delete(_ project: Project, context: ModelContext) throws {
        context.delete(project)
        try context.save()
    }

    static func allProjects(_ context: ModelContext) -> [Project] {
        (try? context.fetch(FetchDescriptor<Project>())) ?? []
    }
}
