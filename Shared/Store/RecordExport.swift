import Foundation
import SwiftData

/// 기록 내보내기(TRK-47). 사람이 읽을 수 있게 정렬한 UTF-8 JSON. 형식은 docs/SPEC.md 「기록 탭」.
///
/// - 전체: 모든 프로젝트 + 프로젝트에 붙지 않은 카드·세션·이벤트·지침 문서(`unassigned`).
/// - 프로젝트 하나: 그 프로젝트에 붙은 것만(이벤트는 바뀌지 않는 `Event.project`로 가른다). `unassigned`는 없다.
/// - 넣지 않는 것: 앱이 돌며 쓰는 상태 값(`RecordScope.attributes`의 `exported == false`).
/// - 카드는 표시 ID(`LDG-14`), 세션은 세션 ID로 서로 가리킨다.
public enum RecordExport {

    /// 형식을 바꾸면 올린다(필드 더하기는 그대로, 이름·뜻을 바꾸면 올린다).
    public static let formatVersion = 1

    public struct Document: Codable, Equatable, Sendable {
        public var formatVersion: Int
        public var exportedAt: Date
        public var app: AppInfo
        /// `all` 또는 `project`
        public var scope: String
        public var projects: [ProjectRecord]
        public var unassigned: Unassigned?
    }

    public struct AppInfo: Codable, Equatable, Sendable {
        public var version: String
        public var build: String
        public var schemaVersion: String
    }

    public struct Unassigned: Codable, Equatable, Sendable {
        public var cards: [CardRecord]
        public var sessions: [SessionRecord]
        public var events: [EventRecord]
        public var guideDocs: [GuideDocRecord]
    }

    public struct ProjectRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var key: String
        public var name: String
        public var summary: String
        public var rootPath: String
        public var stack: [String]
        public var nextCardNumber: Int
        public var createdAt: Date
        public var archivedAt: Date?
        public var cards: [CardRecord]
        public var sessions: [SessionRecord]
        public var events: [EventRecord]
        public var guideDocs: [GuideDocRecord]
    }

    public struct CardRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var displayID: String
        public var number: Int
        public var title: String
        public var body: String
        public var kind: String
        public var status: String
        public var origin: String
        public var originSessionId: String?
        public var parent: String?
        public var criteria: [Criterion]
        public var nextSessionNote: String?
        public var createdAt: Date
        public var updatedAt: Date
        public var doneAt: Date?
        public var sessions: [CardSessionRecord]
    }

    public struct CardSessionRecord: Codable, Equatable, Sendable {
        public var sessionId: String?
        public var attachedAt: Date
        public var detachedAt: Date?
    }

    public struct SessionRecord: Codable, Equatable, Sendable {
        public var id: String
        public var provider: String
        public var kind: String
        public var parent: String?
        public var agentName: String?
        public var cwd: String
        public var gitBranch: String?
        public var startedAt: Date
        public var lastSeenAt: Date
        public var endedAt: Date?
        public var endReason: String?
        public var lastPrompt: String?
        public var lastPromptAt: Date?
    }

    public struct EventRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var at: Date
        public var type: String
        public var card: String?
        public var session: String?
        public var payload: [String: EventValue]?
    }

    public struct GuideDocRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var relPath: String
        public var content: String
        public var draft: String?
        public var conflictContent: String?
        public var isMissing: Bool
        public var lastSyncedAt: Date
        public var versions: [GuideVersionRecord]
    }

    public struct GuideVersionRecord: Codable, Equatable, Sendable {
        public var at: Date
        public var source: String
        public var content: String
    }

    // MARK: - 만들기

    /// - Parameter project: nil이면 전체.
    public static func make(in context: ModelContext, project: Project? = nil, at date: Date = Date(),
                            stamp: StoreVersionStamp = .current()) throws -> Document {
        let app = AppInfo(version: stamp.appVersion, build: stamp.build, schemaVersion: stamp.schemaVersion)
        if let project {
            return Document(formatVersion: formatVersion, exportedAt: date, app: app, scope: "project",
                            projects: [record(project)], unassigned: nil)
        }
        let projects = try context.fetch(FetchDescriptor<Project>()).sorted { ($0.createdAt, $0.key) < ($1.createdAt, $1.key) }
        let unassigned = Unassigned(
            cards: try context.fetch(FetchDescriptor<Card>()).filter { $0.project == nil }.sorted(by: cardOrder).map(record),
            sessions: try context.fetch(FetchDescriptor<Session>()).filter { $0.project == nil }
                .sorted(by: sessionOrder).map(record),
            events: try context.fetch(FetchDescriptor<Event>()).filter { $0.project == nil }
                .sorted(by: eventOrder).map(record),
            guideDocs: try context.fetch(FetchDescriptor<GuideDoc>()).filter { $0.project == nil }
                .sorted { $0.relPath < $1.relPath }.map(record)
        )
        return Document(formatVersion: formatVersion, exportedAt: date, app: app, scope: "all",
                        projects: projects.map(record), unassigned: unassigned)
    }

    public static func encode(_ document: Document) throws -> Data {
        try encoder().encode(document)
    }

    public static func decode(_ data: Data) throws -> Document {
        try decoder().decode(Document.self, from: data)
    }

    /// 파일 이름 제안: `Waypoint-<키 또는 전체>-<yyyy-MM-dd>.json`
    public static func suggestedFileName(project: Project?, at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Waypoint-\(project?.key ?? "전체")-\(formatter.string(from: date)).json"
    }

    // MARK: - 변환

    static func record(_ p: Project) -> ProjectRecord {
        ProjectRecord(
            id: p.id, key: p.key, name: p.name, summary: p.summary, rootPath: p.rootPath, stack: p.stack,
            nextCardNumber: p.nextCardNumber, createdAt: p.createdAt, archivedAt: p.archivedAt,
            cards: (p.cards ?? []).sorted(by: cardOrder).map(record),
            sessions: (p.sessions ?? []).sorted(by: sessionOrder).map(record),
            events: (p.events ?? []).sorted(by: eventOrder).map(record),
            guideDocs: (p.guideDocs ?? []).sorted { $0.relPath < $1.relPath }.map(record)
        )
    }

    static func record(_ c: Card) -> CardRecord {
        CardRecord(
            id: c.id, displayID: c.displayID, number: c.number, title: c.title, body: c.body, kind: c.kindRaw,
            status: c.statusRaw, origin: c.originRaw, originSessionId: c.originSessionId, parent: c.parent?.displayID,
            criteria: c.criteria, nextSessionNote: c.nextSessionNote, createdAt: c.createdAt, updatedAt: c.updatedAt,
            doneAt: c.doneAt,
            sessions: (c.cardSessions ?? []).sorted { $0.attachedAt < $1.attachedAt }.map {
                CardSessionRecord(sessionId: $0.session?.id, attachedAt: $0.attachedAt, detachedAt: $0.detachedAt)
            }
        )
    }

    static func record(_ s: Session) -> SessionRecord {
        SessionRecord(
            id: s.id, provider: s.providerRaw, kind: s.kindRaw, parent: s.parent?.id, agentName: s.agentName,
            cwd: s.cwd, gitBranch: s.gitBranch, startedAt: s.startedAt, lastSeenAt: s.lastSeenAt, endedAt: s.endedAt,
            endReason: s.endReason, lastPrompt: s.lastPrompt, lastPromptAt: s.lastPromptAt
        )
    }

    static func record(_ e: Event) -> EventRecord {
        let payload = e.payload.flatMap { try? JSONDecoder().decode([String: EventValue].self, from: $0) }
        return EventRecord(id: e.id, at: e.at, type: e.typeRaw, card: e.card?.displayID, session: e.session?.id,
                           payload: payload)
    }

    static func record(_ d: GuideDoc) -> GuideDocRecord {
        GuideDocRecord(
            id: d.id, relPath: d.relPath, content: d.content, draft: d.draft, conflictContent: d.conflictContent,
            isMissing: d.isMissing, lastSyncedAt: d.lastSyncedAt,
            versions: (d.versions ?? []).sorted { $0.at < $1.at }.map {
                GuideVersionRecord(at: $0.at, source: $0.sourceRaw, content: $0.content)
            }
        )
    }

    private static func cardOrder(_ a: Card, _ b: Card) -> Bool { (a.number, a.createdAt) < (b.number, b.createdAt) }
    private static func sessionOrder(_ a: Session, _ b: Session) -> Bool { (a.startedAt, a.id) < (b.startedAt, b.id) }
    private static func eventOrder(_ a: Event, _ b: Event) -> Bool {
        (a.at, a.id.uuidString) < (b.at, b.id.uuidString)
    }

    // MARK: - JSON

    /// 밀리초까지 남기는 ISO 8601(UTC). 기본 `.iso8601`은 초 아래를 버린다.
    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter().string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = formatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "날짜 형식 아님: \(text)")
            }
            return date
        }
        return decoder
    }
}
