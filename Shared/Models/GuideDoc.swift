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
