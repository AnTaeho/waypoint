import Foundation
import SwiftData

/// 기록 보관(SPEC 5장 「기록 보관」). 14일이 지난 기록 가운데 카드에 이어지지 않은 것을 지운다.
public enum RecordRetention {

    /// 보관 기간(일). 기간을 바꾸려면 이 값만 고친다.
    public static let days = 14
    public static let interval: TimeInterval = TimeInterval(days) * 24 * 60 * 60
    /// 정리 간격. 앱 시작 직후 한 번, 그 뒤 하루에 한 번.
    public static let runInterval: TimeInterval = 24 * 60 * 60
    /// 한 번에 지우는 최대 수. 남으면 `resumeInterval` 뒤에 이어서 지운다.
    public static let batchLimit = 500
    public static let resumeInterval: TimeInterval = 60

    // MARK: - 판정

    /// 이 시각의 기록이 보관 기간을 넘겼는가. 딱 14일이면 넘긴 것이다(`PromptRetention`과 같다).
    public static func isExpired(at date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) >= interval
    }

    /// 정리를 돌릴 때가 됐는가. 지난번에 다 못 지웠으면 `resumeInterval` 뒤, 아니면 하루 뒤.
    public static func isDue(lastRun: Date?, unfinished: Bool, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= (unfinished ? resumeInterval : runInterval)
    }

    /// 이벤트 하나를 지울 때가 됐는가.
    /// `isLatest`: `file.changed`는 그 카드의, `project.status`는 그 프로젝트의 남길 하나인가(가장 최근 것, 같은 시각이면 그중 하나).
    public static func expires(type: EventType, kind: String?, hasCard: Bool, isLatest: Bool, at date: Date, now: Date) -> Bool {
        guard isExpired(at: date, now: now) else { return false }
        switch type {
        case .guideSynced, .cardAttached, .cardDetached: return true
        case .note: return kind == PromptRetention.promptKind
        case .check, .commit: return !hasCard
        // 카드의 마지막 변경 시각은 근거가 오래됐는지 가리는 데 쓴다(`CardEvidence`).
        case .fileChanged: return !(hasCard && isLatest)
        case .projectStatus: return !isLatest
        default: return false
        }
    }

    /// 세션을 지울 때 같이 지우는 이벤트인가(시작·끝·넘김·프로젝트 옮김·요청).
    public static func goesWithSession(type: EventType, kind: String?) -> Bool {
        switch type {
        case .sessionStart, .sessionEnd, .sessionFiled: true
        case .note: kind == PromptRetention.promptKind || kind == SessionProjectBinding.boundNoteKind
        default: false
        }
    }

    public struct SessionFacts: Equatable, Sendable {
        public var endedAt: Date?
        public var lastSeenAt: Date
        /// 카드 연결이 있었거나 카드에 이어진 기록을 남겼다
        public var hasCardLink: Bool

        public init(endedAt: Date?, lastSeenAt: Date, hasCardLink: Bool) {
            self.endedAt = endedAt
            self.lastSeenAt = lastSeenAt
            self.hasCardLink = hasCardLink
        }
    }

    /// 메인 세션과 그 하위 세션 묶음을 지울 때가 됐는가. 하나라도 남아야 하면 모두 남긴다.
    public static func familyExpires(_ members: [SessionFacts], now: Date) -> Bool {
        guard !members.isEmpty else { return false }
        return members.allSatisfy { member in
            guard let endedAt = member.endedAt, !member.hasCardLink else { return false }
            return isExpired(at: endedAt, now: now) && isExpired(at: member.lastSeenAt, now: now)
        }
    }

    /// 지침 문서의 판 하나를 지울 때가 됐는가. 문서마다 가장 최근 판은 남긴다.
    public static func versionExpires(at date: Date, isLatest: Bool, now: Date) -> Bool {
        !isLatest && isExpired(at: date, now: now)
    }

    // MARK: - 적용

    public struct Result: Equatable, Sendable {
        public var events = 0
        public var sessions = 0
        public var versions = 0
        /// 상한에 닿아 지울 것이 남았을 수 있다
        public var unfinished = false

        public var total: Int { events + sessions + versions }
    }

    /// 기간이 지난 기록을 `limit`개까지 지운다. 저장은 부르는 쪽이 한다.
    @discardableResult
    public static func apply(in context: ModelContext, now: Date, limit: Int = batchLimit) -> Result {
        var run = Run(context: context, now: now, limit: limit)
        let steps: [(inout Run) -> Void] = [
            { $0.plainEvents() }, { $0.cardFileChanges() }, { $0.projectStatuses() }, { $0.prompts() },
            { $0.sessions() }, { $0.guideVersions() },
        ]
        for step in steps where run.left > 0 { step(&run) }
        run.deleteEvents()
        run.result.unfinished = run.left <= 0
        return run.result
    }
}

/// 정리 한 번. 종류마다 질의를 따로 한다.
private struct Run {
    let context: ModelContext
    let now: Date
    let limit: Int
    let cutoff: Date
    var result = RecordRetention.Result()
    /// 지우기로 한 이벤트. 끝에 한꺼번에 지운다.
    var doomed: [PersistentIdentifier: Event] = [:]

    init(context: ModelContext, now: Date, limit: Int) {
        self.context = context
        self.now = now
        self.limit = limit
        cutoff = now.addingTimeInterval(-RecordRetention.interval)
    }

    var left: Int { limit - result.total }

    func expires(_ event: Event, kind: String? = nil, isLatest: Bool = false) -> Bool {
        RecordRetention.expires(type: event.type, kind: kind, hasCard: event.card != nil, isLatest: isLatest,
                                at: event.at, now: now)
    }

    mutating func delete(_ event: Event) {
        guard doomed.updateValue(event, forKey: event.persistentModelID) == nil else { return }
        result.events += 1
    }

    /// 프로젝트의 이벤트 목록에서 한 번에 떼고 지운다(하나씩 떼면 프로젝트 이벤트 수만큼씩 걸린다).
    func deleteEvents() {
        var projects: [PersistentIdentifier: Project] = [:]
        for event in doomed.values {
            if let project = event.project { projects[project.persistentModelID] = project }
        }
        for project in projects.values {
            project.events = (project.events ?? []).filter { doomed[$0.persistentModelID] == nil }
        }
        for event in doomed.values { context.delete(event) }
    }

    func fetch(_ predicate: Predicate<Event>, limit: Int? = nil) -> [Event] {
        var descriptor = FetchDescriptor<Event>(predicate: predicate, sortBy: [SortDescriptor(\.at)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 시각·종류만으로 정해지는 것: 지침 동기화, 세션 연결·해제, 카드 없는 검증·커밋·파일 변경.
    mutating func plainEvents() {
        let cutoff = cutoff
        for type in [EventType.guideSynced, .cardAttached, .cardDetached] where left > 0 {
            let raw = type.rawValue
            for event in fetch(#Predicate { $0.typeRaw == raw && $0.at <= cutoff }, limit: left) where expires(event) {
                delete(event)
            }
        }
        for type in [EventType.check, .commit, .fileChanged] where left > 0 {
            let raw = type.rawValue
            for event in fetch(#Predicate { $0.typeRaw == raw && $0.at <= cutoff && $0.card == nil }, limit: left)
            where expires(event) {
                delete(event)
            }
        }
    }

    /// 가장 최근 것 하나. 시각이 같으면 ID가 큰 쪽이라 실행을 거듭해도 같은 것이 남는다.
    static func keeper(_ events: [Event]) -> Event? {
        events.max { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }
    }

    /// 카드에 이어진 파일 변경. 카드마다 가장 최근 것 하나만 남긴다.
    mutating func cardFileChanges() {
        let cutoff = cutoff
        let raw = EventType.fileChanged.rawValue
        // 남기는 것은 카드마다 하나라, 그만큼 더 읽으면 지울 것이 가려지지 않는다.
        let cards = (try? context.fetchCount(FetchDescriptor<Card>())) ?? 0
        var kept: [PersistentIdentifier: UUID] = [:]
        for event in fetch(#Predicate { $0.typeRaw == raw && $0.at <= cutoff && $0.card != nil }, limit: left + cards) {
            guard left > 0 else { break }
            guard let card = event.card else { continue }
            let id = card.persistentModelID
            let keep = kept[id] ?? {
                var descriptor = FetchDescriptor<Event>(
                    predicate: #Predicate { $0.typeRaw == raw && $0.card?.persistentModelID == id },
                    sortBy: [SortDescriptor(\.at, order: .reverse)])
                descriptor.fetchLimit = 1
                guard let newest = (try? context.fetch(descriptor))?.first?.at else { return event.id }
                let tied = fetch(#Predicate { $0.typeRaw == raw && $0.card?.persistentModelID == id && $0.at == newest })
                return Self.keeper(tied)?.id ?? event.id
            }()
            kept[id] = keep
            if expires(event, isLatest: event.id == keep) { delete(event) }
        }
    }

    /// 프로젝트 지금 상황. 프로젝트마다 가장 최근 것 하나만 남긴다.
    mutating func projectStatuses() {
        let all = ProjectStatus.fetch(.projectStatus, in: context)
        let kept = Set(Dictionary(grouping: all.filter { $0.project != nil }) { $0.project?.id }
            .values.compactMap { Self.keeper($0)?.id })
        for event in all where left > 0 {
            if expires(event, isLatest: kept.contains(event.id)) { delete(event) }
        }
    }

    /// 요청 이벤트. 종류가 payload에 있어 메모를 읽어서 가린다.
    mutating func prompts() {
        let cutoff = cutoff
        let raw = EventType.note.rawValue
        for event in fetch(#Predicate { $0.typeRaw == raw && $0.at <= cutoff }) where left > 0 {
            if expires(event, kind: event.payloadValues["kind"]?.stringValue) { delete(event) }
        }
    }

    /// 카드에 이어지지 않은 끝난 세션. 메인 세션과 하위 세션을 한 묶음으로 본다.
    mutating func sessions() {
        let cutoff = cutoff
        let past = Date.distantPast
        var roots = Set((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate {
            $0.parent == nil && $0.endedAt != nil && $0.lastSeenAt <= cutoff
        }))) ?? [])
        // 카드 연결이 있는 묶음은 객체를 읽기 전에 뺀다(계속 남아 해마다 늘어난다).
        roots.subtract((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate { session in
            session.parent == nil && session.endedAt != nil && session.lastSeenAt <= cutoff
                && ((session.cardSessions?.contains { $0.attachedAt > past } ?? false)
                    || (session.children?.contains { child in
                        child.cardSessions?.contains { $0.attachedAt > past } ?? false
                    } ?? false))
        }))) ?? [])
        for id in roots where left > 0 {
            guard let root = context.model(for: id) as? Session, !root.isDeleted else { continue }
            let family = [root] + (root.children ?? [])
            guard RecordRetention.familyExpires(family.map(facts), now: now) else { continue }
            for member in family.reversed() {
                for event in member.events ?? []
                where RecordRetention.goesWithSession(type: event.type, kind: event.payloadValues["kind"]?.stringValue) {
                    delete(event)
                }
                context.delete(member)
                result.sessions += 1
            }
        }
    }

    func facts(_ session: Session) -> RecordRetention.SessionFacts {
        let linked = !(session.cardSessions ?? []).isEmpty
            || (session.events ?? []).contains { doomed[$0.persistentModelID] == nil && $0.card != nil }
        return RecordRetention.SessionFacts(endedAt: session.endedAt, lastSeenAt: session.lastSeenAt, hasCardLink: linked)
    }

    /// 지침 문서의 이전 판. 문서마다 가장 최근 판은 남긴다.
    mutating func guideVersions() {
        let cutoff = cutoff
        let old = (try? context.fetch(FetchDescriptor<GuideVersion>(predicate: #Predicate { $0.at <= cutoff }))) ?? []
        for version in old where left > 0 {
            let newest = version.doc.flatMap { ($0.versions ?? []).map(\.at).max() }
            let latest = newest.map { version.at >= $0 } ?? false
            guard RecordRetention.versionExpires(at: version.at, isLatest: latest, now: now) else { continue }
            context.delete(version)
            result.versions += 1
        }
    }
}
