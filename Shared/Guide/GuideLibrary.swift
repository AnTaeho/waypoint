import Foundation
import SwiftData

/// 지침 문서 등록·로컬 변경 반영·앱 저장·충돌 해결. 파일 쓰기와 기록 갱신을 한 번에 해서
/// 감시 콜백이 「새 파일 + 옛 해시」를 보는 틈이 없게 한다(메인 스레드에서 부른다).
public enum GuideLibrary {

    /// 문서당 남기는 버전 수. 넘으면 오래된 것부터 지운다.
    public static let versionLimit = 50

    public enum Failure: Error, Equatable {
        case noRoot
        case outsideRoot
        case alreadyRegistered
        case fileMissing
    }

    /// 앱 저장 결과.
    public enum SaveResult: Equatable, Sendable {
        case saved
        /// 편집하는 사이 파일이 바뀌어 멈췄다. `conflictContent`에 로컬 내용이 들어 있다.
        case conflict
    }

    public static func fileURL(of doc: GuideDoc) -> URL? {
        guard let project = doc.project else { return nil }
        return GuidePaths.fileURL(rootPath: project.rootPath, relPath: doc.relPath)
    }

    /// 파일 내용으로 문서를 만들고 버전(local)과 `guide.synced`를 남긴 뒤 저장한다.
    @discardableResult
    public static func register(_ relPath: String, in project: Project, at date: Date, context: ModelContext) throws -> GuideDoc {
        let doc = try add(relPath, to: project, at: date, context: context)
        try context.save()
        return doc
    }

    /// `register`에서 저장만 뺀 것. 프로젝트 등록처럼 여러 변경을 한 번에 저장할 때 쓴다.
    @discardableResult
    public static func add(_ relPath: String, to project: Project, at date: Date, context: ModelContext) throws -> GuideDoc {
        guard let url = GuidePaths.fileURL(rootPath: project.rootPath, relPath: relPath) else { throw Failure.noRoot }
        if (project.guideDocs ?? []).contains(where: { $0.relPath == relPath }) { throw Failure.alreadyRegistered }
        guard case .present(let content, let hash) = try GuideFile.read(url) else { throw Failure.fileMissing }
        let doc = GuideDoc(relPath: relPath, content: content, contentHash: hash, lastSyncedAt: date)
        context.insert(doc)
        doc.project = project
        record(doc, content: content, source: .local, at: date, context: context)
        return doc
    }

    /// 등록만 푼다. 파일은 그대로.
    public static func unregister(_ doc: GuideDoc, context: ModelContext) throws {
        context.delete(doc)
        try context.save()
    }

    /// 로컬 파일을 읽어 판정대로 반영한다. 읽기 오류는 아무것도 하지 않는다.
    @discardableResult
    public static func check(_ doc: GuideDoc, at date: Date, context: ModelContext) -> GuideSync.Decision {
        guard let url = fileURL(of: doc), let disk = try? GuideFile.read(url) else { return .none }
        let decision = GuideSync.decide(
            storedContent: doc.content, storedHash: doc.contentHash,
            draft: doc.draft, wasMissing: doc.isMissing, disk: disk
        )
        switch decision {
        case .none:
            return decision
        case .applyLocal(let content):
            accept(doc, content: content, source: .local, at: date, context: context)
        case .conflict(let content):
            doc.conflictContent = content
            doc.isMissing = false
        case .markMissing:
            doc.isMissing = true
        case .clearMissing:
            doc.isMissing = false
        }
        try? context.save()
        return decision
    }

    /// 모든 등록 문서를 확인한다(앱 시작·감시 재시작 때).
    public static func checkAll(at date: Date, context: ModelContext) {
        let docs = (try? context.fetch(FetchDescriptor<GuideDoc>())) ?? []
        for doc in docs { check(doc, at: date, context: context) }
    }

    /// 편집 내용을 저장한다. 파일이 마지막 동기화 뒤 바뀌었으면 쓰지 않고 충돌로 멈춘다.
    public static func save(_ doc: GuideDoc, content: String, at date: Date, context: ModelContext) throws -> SaveResult {
        guard let url = fileURL(of: doc) else { throw Failure.noRoot }
        switch GuideSync.checkBeforeSave(storedHash: doc.contentHash, disk: try GuideFile.read(url)) {
        case .conflict(let local):
            doc.draft = content
            doc.conflictContent = local
            doc.isMissing = false
            try context.save()
            return .conflict
        case .write:
            if content == doc.content && !doc.isMissing {
                doc.draft = nil
            } else {
                try GuideFile.writeAtomically(content, to: url)
                accept(doc, content: content, source: .app, at: date, context: context)
            }
            try context.save()
            return .saved
        }
    }

    /// 충돌에서 로컬 파일을 고른다: 편집을 버리고 지금 파일 내용을 반영한다.
    public static func keepLocal(_ doc: GuideDoc, at date: Date, context: ModelContext) throws {
        guard let url = fileURL(of: doc) else { throw Failure.noRoot }
        doc.draft = nil
        doc.conflictContent = nil
        switch try GuideFile.read(url) {
        case .missing:
            doc.isMissing = true
        case .present(let content, let hash):
            doc.isMissing = false
            if hash != doc.contentHash {
                accept(doc, content: content, source: .local, at: date, context: context)
            }
        }
        try context.save()
    }

    /// 충돌에서 앱 내용을 고른다: 편집을 파일에 쓴다.
    public static func keepApp(_ doc: GuideDoc, at date: Date, context: ModelContext) throws {
        guard let url = fileURL(of: doc) else { throw Failure.noRoot }
        let content = doc.draft ?? doc.content
        try GuideFile.writeAtomically(content, to: url)
        accept(doc, content: content, source: .app, at: date, context: context)
        try context.save()
    }

    /// 지난 버전 내용으로 저장한다(버전 app). 저장 안 한 편집은 이 내용으로 바뀐다. 충돌 규칙은 저장과 같다.
    public static func revert(_ doc: GuideDoc, to version: GuideVersion, at date: Date, context: ModelContext) throws -> SaveResult {
        doc.draft = version.content == doc.content ? nil : version.content
        return try save(doc, content: version.content, at: date, context: context)
    }

    /// 최신순 버전.
    public static func versions(of doc: GuideDoc) -> [GuideVersion] {
        (doc.versions ?? []).sorted { $0.at > $1.at }
    }

    // MARK: - 내부

    /// 내용을 동기화된 값으로 받아들이고 버전·이벤트를 남긴다.
    private static func accept(_ doc: GuideDoc, content: String, source: GuideSource, at date: Date, context: ModelContext) {
        doc.content = content
        doc.contentHash = GuideFile.hash(content)
        doc.lastSyncedAt = date
        doc.draft = nil
        doc.conflictContent = nil
        doc.isMissing = false
        record(doc, content: content, source: source, at: date, context: context)
    }

    private static func record(_ doc: GuideDoc, content: String, source: GuideSource, at date: Date, context: ModelContext) {
        let version = GuideVersion(content: content, at: date, source: source)
        context.insert(version)
        version.doc = doc
        let all = (doc.versions ?? []) + ((doc.versions ?? []).contains { $0 === version } ? [] : [version])
        for old in all.sorted(by: { $0.at > $1.at }).dropFirst(versionLimit) {
            context.delete(old)
        }
        Event.record(.guideSynced, in: context, project: doc.project, at: date,
                     payload: ["relPath": .string(doc.relPath), "source": .string(source.rawValue)])
    }
}
