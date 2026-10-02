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
    }

    /// 이 프로젝트의 정리 안 된 작업, 최근 것부터. `SessionStart` 응답 안에서 불리므로(훅 타임아웃 1초) 세션은 `sessionIDs`로
    /// 고르고, 파일 목록(payload)은 앞의 `limit`개 세션 것만 읽는다.
    /// `excluding`: 지금 블록을 받는 세션(재개로 다시 열린 세션이 자기 자신을 보지 않게).
    public static func items(for project: Project, now: Date, limit: Int = .max, excluding current: Session? = nil) -> [Item] {
        guard let context = project.modelContext else { return [] }
        let ids = Array(sessionIDs(for: project, in: context, now: now, excluding: current))
        guard !ids.isEmpty else { return [] }
        // 한 번에 읽는다(세션마다 따로 읽지 않게).
        let found = ((try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate<Session> {
            ids.contains($0.persistentModelID)
        }))) ?? []).sorted {
            $0.lastSeenAt != $1.lastSeenAt ? $0.lastSeenAt > $1.lastSeenAt : $0.id < $1.id
        }
        return found.enumerated().map { index, session in
            Item(session: session, files: index < limit ? paths(changes(of: session, project: project, in: context, now: now)) : [])
        }
    }

    /// `items(for:now:)`의 개수만(파일 목록·정렬 없이). 상황판이 다시 그릴 때마다 부른다.
    public static func count(for project: Project, now: Date) -> Int {
        guard let context = project.modelContext else { return 0 }
        return sessionIDs(for: project, in: context, now: now, excluding: nil).count
    }

    /// 조건에 맞는 세션의 ID, 순서 없음.
    ///
    /// 세션·이벤트 객체를 많이 읽지 않게 조건을 질의(하위 질의 포함)로 넘기고 ID만 받는다(TRK-66). 질의 수는 기록 양과 상관없이
    /// 고정이다. 끝난 세션마다 `fetchCount`를 부르던 예전 방식은 끝난 세션 1,600개 저장소에서 대시보드를 한 번 그릴 때 4초 넘게 걸렸고,
    /// 이 프로젝트의 파일 변경을 모두 읽어 세션별로 묶는 방식도 2,500건에서 50 ms를 넘었다.
    static func sessionIDs(for project: Project, in context: ModelContext, now: Date,
                           excluding current: Session?) -> Set<PersistentIdentifier> {
        let cutoff = now.addingTimeInterval(-window)
        let main = SessionKind.main.rawValue
        let subagent = SessionKind.subagent.rawValue
        let raw = EventType.fileChanged.rawValue
        let projectID = project.id
        // 끝난 메인 세션 중 이 프로젝트에 최근 14일 카드 없는 파일 변경을 직접 또는 서브에이전트가 남긴 것. ID만 받는다.
        let changed = #Predicate<Session> { session in
            session.kindRaw == main && session.lastSeenAt >= cutoff && session.endedAt != nil
                && session.project?.id == projectID
                && ((session.events?.contains {
                    $0.typeRaw == raw && $0.at >= cutoff && $0.card == nil && $0.project?.id == projectID
                } ?? false)
                    || (session.children?.contains { child in
                        child.kindRaw == subagent && (child.events?.contains {
                            $0.typeRaw == raw && $0.at >= cutoff && $0.card == nil && $0.project?.id == projectID
                        } ?? false)
                    } ?? false))
        }
        var found = Set((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: changed))) ?? [])
        if let current { found.remove(current.persistentModelID) }
        guard !found.isEmpty else { return [] }
        // 세션이나 하위 세션이 카드에 붙은 적 있는 것(`everAttached`)은 뺀다.
        let past = Date.distantPast
        let attached = #Predicate<Session> { session in
            session.kindRaw == main && session.lastSeenAt >= cutoff && session.endedAt != nil
                && session.project?.id == projectID
                && ((session.cardSessions?.contains { $0.attachedAt > past } ?? false)
                    || (session.children?.contains { child in
                        child.cardSessions?.contains { $0.attachedAt > past } ?? false
                    } ?? false))
        }
        found.subtract((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: attached))) ?? [])
        guard !found.isEmpty else { return [] }
        // 이미 처리한(넘김·연결 기록) 세션
        let filed = Array(filedSessionIDs(for: project))
        if !filed.isEmpty {
            found.subtract((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate<Session> {
                filed.contains($0.id)
            }))) ?? [])
        }
        // 저장 전에 다시 열린 세션은 뺀다(저장된 값은 질의가 이미 걸렀다). 세션 객체를 하나씩 읽지 않으려고 바뀐 것만 본다.
        for case let session as Session in context.insertedModelsArray + context.changedModelsArray where session.endedAt == nil {
            found.remove(session.persistentModelID)
        }
        return found
    }

    /// 세션(과 서브에이전트)이 이 프로젝트에 최근 14일 남긴 카드 없는 `file.changed`.
    static func changes(of session: Session, project: Project, in context: ModelContext, now: Date) -> [Event] {
        let cutoff = now.addingTimeInterval(-window)
        let raw = EventType.fileChanged.rawValue
        let projectID = project.id
        // 서브에이전트가 많아도 질의 하나로
        let owners = ([session] + (session.children ?? []).filter { $0.kind == .subagent }).map(\.persistentModelID)
        return (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate<Event> { event in
            event.typeRaw == raw && event.card == nil && event.at >= cutoff && event.project?.id == projectID
                && (event.session.flatMap { owners.contains($0.persistentModelID) } ?? false)
        }))) ?? []
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
