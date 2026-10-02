import Foundation
import SwiftData

/// 정리 안 된 작업(TRK-62 안전망): 카드에 한 번도 붙지 않은 채 파일을 바꾸고 끝난 메인 세션.
///
/// 조건: 이 프로젝트의 메인 세션, 끝남(`endedAt`), 마지막 활동(`lastSeenAt`)이 최근 14일, 세션·서브에이전트가 카드 연결
/// (`CardSession`)을 한 번도 갖지 않음, 최근 14일 안에 이 프로젝트에 남긴 카드 없는 `file.changed`가 1개 이상(서브에이전트 것 포함),
/// `session.filed`가 아직 없음.
public enum UnfiledWork {
    public static let window: TimeInterval = 14 * 24 * 3600
    /// 시작 블록에 보이는 최대 개수
    public static let blockLimit = 3
    /// 한 줄에 보이는 파일 수
    public static let fileLimit = 3

    public struct Item {
        public let session: Session
        /// 바뀐 파일(프로젝트 기준 상대 경로), 많이 바뀐 것부터. `items(limit:)` 밖의 항목은 비어 있다.
        public let files: [String]
        /// 카드 없는 `file.changed` 수
        public let eventCount: Int
    }

    /// 이 프로젝트의 정리 안 된 작업, 최근 것부터. `SessionStart` 응답 안에서 불리므로(훅 타임아웃 1초) 질의를 이 프로젝트·
    /// 최근 14일로 묶고, 세션은 ID만 먼저 가져온 뒤 카드 없는 파일 변경이 있는 세션만 읽는다. 파일 목록(payload)은 `limit`개만 채운다.
    /// `excluding`: 지금 블록을 받는 세션(재개로 다시 열린 세션이 자기 자신을 보지 않게).
    public static func items(for project: Project, now: Date, limit: Int = .max, excluding current: Session? = nil) -> [Item] {
        guard let context = project.modelContext else { return [] }
        let cutoff = now.addingTimeInterval(-window)
        let main = SessionKind.main.rawValue
        let projectID = project.id
        var ended = Set((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.kindRaw == main && $0.lastSeenAt >= cutoff && $0.endedAt != nil && $0.project?.id == projectID
        }))) ?? [])
        if let current { ended.remove(current.persistentModelID) }
        guard !ended.isEmpty else { return [] }
        let raw = EventType.fileChanged.rawValue
        let events = (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate<Event> {
            $0.typeRaw == raw && $0.at >= cutoff && $0.card == nil && $0.project?.id == projectID
        }))) ?? []

        // 이벤트의 세션(서브에이전트면 부모) → 끝난 메인 세션. 같은 세션은 한 번만 읽는다.
        var owner: [PersistentIdentifier: PersistentIdentifier?] = [:]
        func mainID(of id: PersistentIdentifier, _ session: Session?) -> PersistentIdentifier? {
            if ended.contains(id) { return id }
            if let known = owner[id] { return known }
            let parent = session?.kind == .subagent ? session?.parent?.persistentModelID : nil
            let result = parent.flatMap { ended.contains($0) ? $0 : nil }
            owner[id] = result
            return result
        }
        var grouped: [PersistentIdentifier: [Event]] = [:]
        for event in events {
            guard let session = event.session, let id = mainID(of: session.persistentModelID, session) else { continue }
            grouped[id, default: []].append(event)
        }
        guard !grouped.isEmpty else { return [] }
        let filed = filedSessionIDs(for: project)
        let found = grouped.compactMap { id, events -> (Session, [Event])? in
            guard let session = context.model(for: id) as? Session, session.endedAt != nil,
                  !filed.contains(session.id), !everAttached(session)
            else { return nil }
            return (session, events)
        }.sorted { $0.0.lastSeenAt > $1.0.lastSeenAt }
        return found.enumerated().map { index, entry in
            Item(session: entry.0, files: index < limit ? paths(entry.1) : [], eventCount: entry.1.count)
        }
    }

    /// `items(for:now:)`의 개수만. 상황판처럼 자주 다시 그리는 곳용이다: 카드 없는 `file.changed`를 모두 읽지 않고,
    /// 조건이 맞는 끝난 메인 세션(넘김·연결 기록 없음, 카드에 붙은 적 없음)마다 그 세션·서브에이전트의 카드 없는
    /// 파일 변경이 있는지만 센다(`fetchCount`). 실제 저장소 사본(프로젝트 4개)에서 `items` 40–95 ms → 이 경로 7–12 ms(기계 부하에 따라).
    public static func count(for project: Project, now: Date) -> Int {
        guard let context = project.modelContext else { return 0 }
        let cutoff = now.addingTimeInterval(-window)
        let main = SessionKind.main.rawValue
        let projectID = project.id
        let ids = (try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.kindRaw == main && $0.lastSeenAt >= cutoff && $0.endedAt != nil && $0.project?.id == projectID
        }))) ?? []
        guard !ids.isEmpty else { return 0 }
        let filed = filedSessionIDs(for: project)
        let raw = EventType.fileChanged.rawValue
        let projectPID = project.persistentModelID
        // 관계는 `persistentModelID`로 비교한다(`?.id` 비교보다 빠르다).
        func hasChange(_ session: Session) -> Bool {
            let owners = [session] + (session.children ?? []).filter { $0.kind == .subagent }
            return owners.contains { owner in
                let sid = owner.persistentModelID
                var descriptor = FetchDescriptor<Event>(predicate: #Predicate<Event> {
                    $0.typeRaw == raw && $0.card == nil && $0.session?.persistentModelID == sid
                        && $0.project?.persistentModelID == projectPID && $0.at >= cutoff
                })
                descriptor.fetchLimit = 1
                return ((try? context.fetchCount(descriptor)) ?? 0) > 0
            }
        }
        return ids.reduce(0) { total, id in
            guard let session = context.model(for: id) as? Session, session.endedAt != nil,
                  !filed.contains(session.id), !everAttached(session), hasChange(session) else { return total }
            return total + 1
        }
    }

    /// 세션이나 그 서브에이전트가 카드에 붙은 적이 있는가(지금 풀렸어도).
    public static func everAttached(_ session: Session) -> Bool {
        ([session] + (session.children ?? [])).contains { !($0.cardSessions ?? []).isEmpty }
    }

    /// `file.changed` 경로, 변경 횟수가 많은 것부터(같으면 최근 것, 그다음 이름순).
    static func paths(_ events: [Event]) -> [String] {
        var counts: [String: (count: Int, last: Date)] = [:]
        for event in events {
            guard let path = event.payloadValues["path"]?.stringValue, !path.isEmpty else { continue }
            let old = counts[path]
            counts[path] = ((old?.count ?? 0) + 1, max(old?.last ?? .distantPast, event.at))
        }
        return counts.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count
                : a.value.last != b.value.last ? a.value.last > b.value.last : a.key < b.key
        }.map(\.key)
    }

    /// 이미 처리한(연결·넘김) 세션 ID.
    public static func filedSessionIDs(for project: Project) -> Set<String> {
        let events = project.modelContext.map { ProjectStatus.fetch(.sessionFiled, in: $0) }
            ?? (project.events ?? []).filter { $0.type == .sessionFiled }
        return Set(events.filter { $0.project === project }.compactMap { $0.payloadValues["sessionId"]?.stringValue })
    }

    // MARK: - 블록 줄

    /// 시작 블록의 짧은 세션 ID: 원본 ID 앞 8자(Codex는 `codex:` 접두사 포함). `work_file`이 앞부분 일치로 받는다.
    public static func shortID(_ session: Session) -> String {
        let short = String(session.sourceID.prefix(8))
        return session.provider == .codex ? "codex:\(short)" : short
    }

    /// `- 어제 14:32 · Claude Code · 파일 3개: a.swift, b.swift, c.swift · 5e1f0c2a`
    public static func line(_ item: Item, now: Date, calendar: Calendar = .current) -> String {
        let shown = item.files.prefix(fileLimit).joined(separator: ", ")
        let rest = item.files.count > fileLimit ? " 외 \(item.files.count - fileLimit)" : ""
        let when = TimeFormat.timestamp(item.session.lastSeenAt, now: now, calendar: calendar)
        return "- \(when) · \(item.session.provider.name) · 파일 \(item.files.count)개: \(shown)\(rest) · \(shortID(item.session))"
    }
}
