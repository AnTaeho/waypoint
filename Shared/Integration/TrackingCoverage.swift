import Foundation
import SwiftData

/// 자동 갱신 지표(TRK-62·63): 최근 30일 프로젝트별로 에이전트가 기록을 얼마나 갱신했는가. 요청 때 저장소에서 계산하고 저장하지 않는다.
/// 숫자와 프로젝트 키만 담는다(프로젝트 이름·경로·세션 ID·대화 없음).
///
/// - 연결률: 바뀐 파일이 있는 끝난 메인 세션 중 카드에 붙었거나(서브에이전트 포함, 지금 풀렸어도) `work_file`로 정리한(연결·넘김) 비율.
/// - 메모 갱신률: 카드에 붙은 끝난 메인 세션 중, 세션 동안(`startedAt`…`endedAt`) 붙었던 카드에 메모(`card_note`)·다음 세션 메모·
///   완료 조건 체크 변경·에이전트 검증 보고 중 하나라도 남은 비율.
/// - 상황 경과: 마지막 `project.status` 이후 일수(없으면 nil).
/// 세션은 마지막 활동(`lastSeenAt`)이 기간 안인 것을 센다.
public struct TrackingCoverage: Equatable, Sendable {
    public static let windowDays = 30

    public struct Row: Equatable, Sendable {
        public let key: String
        /// 바뀐 파일이 있는 끝난 메인 세션
        public var workedSessions = 0
        /// 그중 카드에 붙었거나 정리한 세션
        public var linkedSessions = 0
        /// 카드에 붙은 끝난 메인 세션
        public var attachedSessions = 0
        /// 그중 세션 동안 메모·조건·근거를 남긴 세션
        public var notedSessions = 0
        /// 마지막 상황 갱신 이후 일수
        public var statusAgeDays: Int?

        public init(key: String) { self.key = key }
    }

    public let rows: [Row]

    public init(rows: [Row]) { self.rows = rows }

    public var total: Row {
        var row = Row(key: "")
        for r in rows {
            row.workedSessions += r.workedSessions; row.linkedSessions += r.linkedSessions
            row.attachedSessions += r.attachedSessions; row.notedSessions += r.notedSessions
        }
        return row
    }

    // MARK: - 계산

    /// 저장소에서 기간 안 메인 세션과 상황·정리 이벤트만 읽어 계산한다.
    public static func compute(in context: ModelContext, now: Date) -> TrackingCoverage {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 24 * 3600)
        let main = SessionKind.main.rawValue
        let sessions = (try? context.fetch(FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.kindRaw == main && $0.lastSeenAt >= cutoff }))) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let filed = Set(ProjectStatus.fetch(.sessionFiled, in: context).compactMap { $0.payloadValues["sessionId"]?.stringValue })
        return compute(projects: projects, sessions: sessions, filedSessionIDs: filed,
                       statusDates: ProjectStatus.latestDates(in: context), now: now)
    }

    /// 순수 계산. 보관된 프로젝트는 뺀다. 행은 세는 세션이나 상황이 있는 프로젝트만, 키 순서.
    public static func compute(projects: [Project], sessions: [Session], filedSessionIDs: Set<String>,
                               statusDates: [UUID: Date], now: Date) -> TrackingCoverage {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 24 * 3600)
        var rows: [UUID: Row] = [:]
        let active = projects.filter { $0.archivedAt == nil }
        for project in active {
            var row = Row(key: project.key)
            if let at = statusDates[project.id] { row.statusAgeDays = max(0, Int(now.timeIntervalSince(at) / 86400)) }
            rows[project.id] = row
        }
        for session in sessions where session.kind == .main && session.endedAt != nil && session.lastSeenAt >= cutoff {
            guard let project = session.project, rows[project.id] != nil else { continue }
            let attached = UnfiledWork.everAttached(session)
            if hasChangedFiles(session, in: project) {
                rows[project.id]?.workedSessions += 1
                if attached || filedSessionIDs.contains(session.id) { rows[project.id]?.linkedSessions += 1 }
            }
            if attached {
                rows[project.id]?.attachedSessions += 1
                if leftUpdate(session) { rows[project.id]?.notedSessions += 1 }
            }
        }
        let shown = rows.values.filter { $0.workedSessions + $0.attachedSessions > 0 || $0.statusAgeDays != nil }
        return TrackingCoverage(rows: shown.sorted { $0.key < $1.key })
    }

    static func hasChangedFiles(_ session: Session, in project: Project) -> Bool {
        ([session] + (session.children ?? [])).contains { s in
            (s.events ?? []).contains { $0.type == .fileChanged && $0.project === project }
        }
    }

    /// 세션 동안 붙었던 카드에 메모·다음 세션 메모·조건 체크 변경·에이전트 검증 보고가 남았는가.
    static func leftUpdate(_ session: Session) -> Bool {
        let end = session.endedAt ?? .distantFuture
        let cards = ([session] + (session.children ?? [])).flatMap { $0.cardSessions ?? [] }.compactMap(\.card)
        var seen = Set<UUID>()
        for card in cards where seen.insert(card.id).inserted {
            let found = (card.events ?? []).contains { event in
                guard event.at >= session.startedAt, event.at <= end else { return false }
                switch event.type {
                case .note:
                    let kind = event.payloadValues["kind"]?.stringValue
                    return kind == nil || kind == MCPTools.handoffNoteKind || kind == CardEditing.criterionNoteKind
                case .check:
                    return event.payloadValues["source"]?.stringValue == CheckSource.agent.rawValue
                default:
                    return false
                }
            }
            if found { return true }
        }
        return false
    }

    // MARK: - 내보내기

    static func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "-" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }

    static func statusText(_ days: Int?) -> String {
        guard let days else { return "상황 없음" }
        return days == 0 ? "상황 오늘" : "상황 \(days)일 전"
    }

    /// 진단 내보내기 줄. 숫자와 프로젝트 키만.
    public func diagnosticLines() -> [String] {
        var lines = ["자동 갱신 (최근 \(Self.windowDays)일)"]
        if rows.isEmpty { return lines + ["기록 없음"] }
        let t = total
        lines.append("전체: 카드 연결 \(t.linkedSessions)/\(t.workedSessions) · 메모 갱신 \(t.notedSessions)/\(t.attachedSessions)")
        lines += rows.map {
            "\($0.key): 카드 연결 \($0.linkedSessions)/\($0.workedSessions) · 메모 갱신 \($0.notedSessions)/\($0.attachedSessions) · \(Self.statusText($0.statusAgeDays))"
        }
        return lines
    }

    /// 연동 상태 패널 줄(화면 문구). 센 세션이 없으면 빈 배열.
    public func panelLines() -> [String] {
        let t = total
        var lines: [String] = []
        if t.workedSessions + t.attachedSessions > 0 {
            lines.append("최근 \(Self.windowDays)일 · 카드 연결 \(t.linkedSessions)/\(t.workedSessions) · 메모 갱신 \(t.notedSessions)/\(t.attachedSessions)")
        }
        if !rows.isEmpty {
            let days = Int(ProjectStatus.staleAfter / 86400)
            let fresh = rows.filter { $0.statusAgeDays.map { $0 < days } ?? false }.count
            lines.append("지금 상황 · \(days)일 안에 갱신 \(fresh)/\(rows.count) 프로젝트")
        }
        return lines
    }

    /// `/integration/status`의 `coverage`.
    public var json: JSONValue {
        func rate(_ part: Int, _ whole: Int) -> JSONValue { whole == 0 ? .null : .number(Double(part) / Double(whole)) }
        return [
            "windowDays": JSONValue(Self.windowDays),
            "projects": .array(rows.map { row in
                [
                    "key": .string(row.key),
                    "workedSessions": JSONValue(row.workedSessions),
                    "linkedSessions": JSONValue(row.linkedSessions),
                    "linkRate": rate(row.linkedSessions, row.workedSessions),
                    "attachedSessions": JSONValue(row.attachedSessions),
                    "notedSessions": JSONValue(row.notedSessions),
                    "noteRate": rate(row.notedSessions, row.attachedSessions),
                    "statusAgeDays": row.statusAgeDays.map { JSONValue($0) } ?? .null,
                ]
            }),
        ]
    }
}
