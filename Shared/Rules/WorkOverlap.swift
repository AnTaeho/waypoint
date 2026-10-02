import Foundation
import SwiftData

/// 같은 파일 작업 중(TRK-17): 같은 프로젝트에서 끝나지 않은 작업 단위 둘 이상이 **같은 체크아웃**의 **같은 파일**을
/// 각자 최근 `window` 안에 바꿨으면 겹침이다. 실제 git 충돌이 났다는 뜻이 아니다(덮어쓰기 위험을 미리 알린다).
///
/// - 작업 단위: 메인 세션과 그 서브에이전트 전부(뿌리 메인 세션 ID). 부모와 서브에이전트, 같은 부모의 서브에이전트끼리는
///   겹침으로 보지 않는다(부모가 나눠 맡긴 일이라 그 세션이 조정한다).
/// - 끝나지 않음: 뿌리 메인 세션이 `endedAt` 없고 `SessionRules.state`가 ended가 아님(대시보드 작업중 줄과 같은 기준).
///   단위가 살아 있으면 이미 끝난 서브에이전트의 변경도 단위의 변경으로 센다(같은 작업 트리에 남아 있다).
/// - 같은 체크아웃: `file.changed` payload의 `checkout`(그 파일의 git 작업 트리 최상위 절대 경로)이 같음.
///   `checkout`이 없는 기록(TRK-17 전 기록, git 밖 파일)은 겹침 판정에서 뺀다(경고하지 않는 쪽으로 누락).
/// - 같은 파일: payload `path`(프로젝트 `rootPath` 기준 상대 경로)가 같음. 같은 프로젝트·같은 체크아웃 안이면 상대 경로가 파일을 가른다.
public enum WorkOverlap {
    /// 각자 이 시간 안에 바꾼 파일만 본다(60분, 경계 포함).
    public static let window: TimeInterval = 60 * 60
    /// MCP 응답 `overlaps`에 싣는 파일 수
    public static let agentFileLimit = 5
    /// 시작 블록 「다른 세션에서 작업중」 줄에 붙이는 최근 파일 수
    public static let blockFileLimit = 3

    // MARK: - 순수 판정

    /// 파일 변경 한 건.
    public struct Touch: Hashable, Sendable {
        /// 작업 단위(뿌리 메인 세션 ID)
        public let unit: String
        /// 바꾼 세션 ID(서브에이전트면 그 ID)
        public let session: String
        /// git 작업 트리 최상위 절대 경로. 모르면 nil
        public let checkout: String?
        public let path: String
        public let at: Date

        public init(unit: String, session: String, checkout: String?, path: String, at: Date) {
            self.unit = unit
            self.session = session
            self.checkout = checkout
            self.path = path
            self.at = at
        }
    }

    /// 한 단위가 본 상대 단위 하나와의 겹침.
    public struct Pair: Hashable, Sendable {
        public let unit: String
        public let other: String
        /// 겹친 파일. 두 쪽 중 늦은 변경이 최근인 것부터(같으면 이름순)
        public let files: [String]
    }

    /// 겹침 전부. 양쪽 방향(a가 본 b, b가 본 a)을 모두 낸다. 순서: 단위 ID, 파일 많은 상대, 상대 ID.
    /// - live: 끝나지 않은 단위 ID. 여기 없는 단위의 변경은 보지 않는다.
    public static func pairs(_ touches: [Touch], live: Set<String>, now: Date,
                             window: TimeInterval = WorkOverlap.window) -> [Pair] {
        struct FileKey: Hashable { let checkout: String; let path: String }
        var byFile: [FileKey: [String: Date]] = [:]
        for touch in touches where live.contains(touch.unit) && now.timeIntervalSince(touch.at) <= window {
            guard let checkout = touch.checkout, !checkout.isEmpty, !touch.path.isEmpty else { continue }
            let key = FileKey(checkout: checkout, path: touch.path)
            let last = byFile[key]?[touch.unit] ?? .distantPast
            byFile[key, default: [:]][touch.unit] = max(last, touch.at)
        }
        struct PairKey: Hashable { let unit: String; let other: String }
        var shared: [PairKey: [String: Date]] = [:]
        for (key, units) in byFile where units.count > 1 {
            for (unit, at) in units {
                for (other, otherAt) in units where other != unit {
                    let pair = PairKey(unit: unit, other: other)
                    let latest = max(at, otherAt)
                    shared[pair, default: [:]][key.path] = max(shared[pair]?[key.path] ?? .distantPast, latest)
                }
            }
        }
        return shared.map { key, files in
            Pair(unit: key.unit, other: key.other, files: files.sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
            }.map(\.key))
        }.sorted {
            if $0.unit != $1.unit { return $0.unit < $1.unit }
            if $0.files.count != $1.files.count { return $0.files.count > $1.files.count }
            return $0.other < $1.other
        }
    }

    /// 같은 상대·같은 파일 집합은 한 번만 알린다(TRK-17 「알림 빈도」). 이미 알린 파일에 없는 파일이 끼면 다시 알린다.
    /// - Returns: 알릴지, 알린 뒤의 파일 집합
    public static func shouldReport(_ files: [String], reported: Set<String>) -> (report: Bool, reported: Set<String>) {
        let current = Set(files)
        guard !current.isEmpty, !current.isSubset(of: reported) else { return (false, reported) }
        return (true, reported.union(current))
    }

    // MARK: - 저장소에서

    /// 상대 단위 하나와의 겹침(화면·MCP·블록용).
    public struct Overlap {
        /// 상대 작업 단위의 메인 세션
        public let other: Session
        /// 상대 단위(메인·끝나지 않은 서브에이전트)가 붙어 있는 카드, 번호순
        public let cards: [Card]
        /// 겹친 파일, 최근 것부터
        public let files: [String]

        /// 상대를 부르는 짧은 이름: 카드가 있으면 첫 카드 ID, 없으면 세션 표시(`sess·1a2b`, Codex는 앞에 `Codex · `).
        public var label: String { cards.first?.displayID ?? SessionFormat.label(for: other) }
    }

    /// 한 프로젝트의 최근 `window` 파일 변경(끝나지 않은 단위만)과 겹침.
    public struct Index {
        let touches: [Touch]
        let pairs: [String: [Pair]]
        let sessions: [String: Session]

        public static var empty: Index { Index(touches: [], pairs: [:], sessions: [:]) }

        public var isEmpty: Bool { pairs.isEmpty }

        /// 이 세션이 본 겹침. 메인 세션이면 단위 전체(서브에이전트 포함)의 변경으로, 서브에이전트면 그 세션의 변경만으로.
        public func overlaps(for session: Session) -> [Overlap] {
            let unit = WorkOverlap.root(of: session)
            guard let found = pairs[unit.id], !found.isEmpty else { return [] }
            let mine: Set<String>? = session === unit ? nil
                : Set(touches.filter { $0.session == session.id }.map(\.path))
            return found.compactMap { pair in
                let files = mine.map { mine in pair.files.filter(mine.contains) } ?? pair.files
                guard !files.isEmpty, let other = sessions[pair.other] else { return nil }
                return Overlap(other: other, cards: WorkOverlap.cards(of: other), files: files)
            }
        }

        /// 이 세션(메인이면 서브에이전트 포함)이 최근 `window` 안에 바꾼 파일, 최근 것부터. 체크아웃을 몰라도 넣는다.
        public func recentFiles(of session: Session, limit: Int = .max) -> [String] {
            let isRoot = session.kind == .main
            var last: [String: Date] = [:]
            for touch in touches where isRoot ? touch.unit == session.id : touch.session == session.id {
                last[touch.path] = max(last[touch.path] ?? .distantPast, touch.at)
            }
            return Array(last.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map(\.key).prefix(limit))
        }
    }

    /// 이 프로젝트의 겹침 색인. 질의는 이 프로젝트·최근 `window`의 `file.changed`로 묶는다(시작 블록·대시보드가 자주 부른다).
    public static func index(for project: Project, now: Date,
                             stallTimeout: TimeInterval = SessionRules.defaultStallTimeout) -> Index {
        guard let context = project.modelContext else { return .empty }
        let cutoff = now.addingTimeInterval(-window)
        let raw = EventType.fileChanged.rawValue
        let projectPID = project.persistentModelID
        let events = (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate<Event> {
            $0.typeRaw == raw && $0.at >= cutoff && $0.project?.persistentModelID == projectPID
        }))) ?? []
        guard !events.isEmpty else { return .empty }

        var liveCache: [String: Bool] = [:]
        var sessions: [String: Session] = [:]
        var touches: [Touch] = []
        var seen = Set<Touch>()
        for event in events {
            guard let session = event.session else { continue }
            let unit = root(of: session)
            let isLive = liveCache[unit.id] ?? {
                let live = unit.endedAt == nil
                    && SessionRules.state(of: unit, now: now, stallTimeout: stallTimeout) != .ended
                liveCache[unit.id] = live
                return live
            }()
            guard isLive else { continue }
            let values = event.payloadValues
            guard let path = values["path"]?.stringValue, !path.isEmpty else { continue }
            sessions[unit.id] = unit
            // 카드마다 한 건씩 남긴 같은 변경은 하나로 센다.
            let touch = Touch(unit: unit.id, session: session.id, checkout: values["checkout"]?.stringValue,
                              path: path, at: event.at)
            if seen.insert(touch).inserted { touches.append(touch) }
        }
        let live = Set(liveCache.filter(\.value).keys)
        let found = pairs(touches, live: live, now: now)
        return Index(touches: touches, pairs: Dictionary(grouping: found, by: \.unit), sessions: sessions)
    }

    /// 대시보드 줄마다(`DashboardRow.id`) 겹침. 프로젝트마다 색인을 한 번만 만든다.
    public static func byRow(_ rows: [DashboardRow], now: Date,
                             stallTimeout: TimeInterval = SessionRules.defaultStallTimeout) -> [String: [Overlap]] {
        var indexes: [ObjectIdentifier: Index] = [:]
        var result: [String: [Overlap]] = [:]
        for row in rows {
            guard let project = row.session.project else { continue }
            let key = ObjectIdentifier(project)
            let index = indexes[key] ?? index(for: project, now: now, stallTimeout: stallTimeout)
            indexes[key] = index
            let found = index.overlaps(for: row.session)
            if !found.isEmpty { result[row.id] = found }
        }
        return result
    }

    /// 겹친 파일 수(상대가 여럿이면 합집합).
    public static func fileCount(_ overlaps: [Overlap]) -> Int {
        Set(overlaps.flatMap(\.files)).count
    }

    /// 짧은 표시: 「같은 파일 2개 · PRB-3」, 상대가 여럿이면 「… · PRB-3 외 1」. 없으면 nil.
    public static func summary(_ overlaps: [Overlap]) -> String? {
        guard let first = overlaps.first else { return nil }
        let rest = overlaps.count > 1 ? " 외 \(overlaps.count - 1)" : ""
        return "같은 파일 \(fileCount(overlaps))개 · \(first.label)\(rest)"
    }

    // MARK: - 도우미

    /// 작업 단위의 뿌리(부모를 따라 올라간 메인 세션). 부모가 없는 서브에이전트는 그 자신.
    public static func root(of session: Session) -> Session {
        var current = session
        for _ in 0..<8 {
            guard current.kind == .subagent, let parent = current.parent else { break }
            current = parent
        }
        return current
    }

    /// 단위(메인과 끝나지 않은 서브에이전트)가 붙어 있는 카드, 번호순, 중복 없이.
    static func cards(of unit: Session) -> [Card] {
        let members = [unit] + (unit.children ?? []).filter { $0.endedAt == nil }
        var seen = Set<ObjectIdentifier>()
        return members.flatMap { $0.openCardSessions.compactMap(\.card) }
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
            .sorted { $0.number < $1.number }
    }
}
