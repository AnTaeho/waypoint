import Foundation
import SwiftData

@Model
public final class GuideDoc {
    public var id: UUID = UUID()
    public var project: Project?
    /// 프로젝트 rootPath 기준 상대 경로(예: "CLAUDE.md")
    public var relPath: String = ""
    public var content: String = ""
    public var contentHash: String = ""
    public var lastSyncedAt: Date = Date()
    /// 앱에서 편집하고 아직 파일에 저장하지 않은 원문. `content`와 같으면 nil로 둔다.
    public var draft: String?
    /// 마지막 확인 때 로컬 파일이 없었다(등록은 유지).
    public var isMissing: Bool = false
    /// 저장하지 않은 편집이 있는 동안 로컬 파일이 바뀌어 멈춘 상태면, 그때 읽은 로컬 파일 내용. 고르면 nil.
    public var conflictContent: String?

    @Relationship(deleteRule: .cascade, inverse: \GuideVersion.doc)
    public var versions: [GuideVersion]? = []

    public init(relPath: String, content: String = "", contentHash: String = "", lastSyncedAt: Date = Date()) {
        self.relPath = relPath
        self.content = content
        self.contentHash = contentHash
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
public final class GuideVersion {
    public var doc: GuideDoc?
    public var content: String = ""
    public var at: Date = Date()
    public var sourceRaw: String = GuideSource.local.rawValue

    public init(content: String, at: Date = Date(), source: GuideSource) {
        self.content = content
        self.at = at
        self.sourceRaw = source.rawValue
    }

    public var source: GuideSource {
        get { GuideSource(rawValue: sourceRaw) ?? .local }
        set { sourceRaw = newValue.rawValue }
    }
}
