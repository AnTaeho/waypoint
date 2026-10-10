import Foundation

/// 통합 화면의 집계. 검색·도구 필터와 무관하게 보관되지 않은 프로젝트 전체를 센다.
public struct DashboardOverview {
    public let groups: [DashboardGroup]
    public let liveCount: Int
    /// 멈춘 줄 중 내 답을 기다리지 않는 것
    public let stalledCount: Int
    /// 내 답(승인·질문)을 기다리는 줄
    public let waitingCount: Int
    public let liveProjectCount: Int
    public let nextCount: Int
    public let doneTodayCount: Int
    public let resumeCards: [Card]

    public init(projects: [Project], now: Date, calendar: Calendar = .current) {
        let visible = projects.filter { $0.archivedAt == nil }
        groups = DashboardQuery.groups(for: visible, now: now)
        let rows = groups.flatMap(\.rows)
        liveCount = rows.filter { $0.workState == .live }.count
        let held = Self.split(rows)
        stalledCount = held.resting.count
        waitingCount = held.waiting.count
        liveProjectCount = groups.filter(\.hasLive).count
        let cards = visible.flatMap { $0.cards ?? [] }
        nextCount = cards.filter { $0.status == .next }.count
        let start = calendar.startOfDay(for: now)
        doneTodayCount = cards.filter {
            $0.status == .done && ($0.doneAt.map { $0 >= start && $0 <= now } ?? false)
        }.count
        resumeCards = cards.filter {
            ($0.status == .next || $0.status == .idea)
                && CardRules.workState(of: $0, now: now) == .none
                && !($0.nextSessionNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.displayID < $1.displayID
        }
    }

    /// 멈춘 줄을 내 답을 기다리는 줄과 그 밖으로 가른다. 작업 중 줄은 어느 쪽에도 없다. 순서는 그대로.
    public static func split(_ rows: [DashboardRow]) -> (waiting: [DashboardRow], resting: [DashboardRow]) {
        let stalled = rows.filter { $0.workState == .stalled }
        return (stalled.filter { $0.waitingKind != nil }, stalled.filter { $0.waitingKind == nil })
    }

    public var headline: String { Self.headline(liveProjects: liveProjectCount, waiting: waitingCount) }

    /// 머리말 아래 한 줄.
    public static func headline(liveProjects: Int, waiting: Int) -> String {
        switch (liveProjects > 0, waiting > 0) {
        case (true, true): "\(liveProjects)개 프로젝트에서 작업 중, \(waiting)개 세션이 내 답을 기다립니다."
        case (true, false): "\(liveProjects)개 프로젝트에서 작업 중입니다."
        case (false, true): "\(waiting)개 세션이 내 답을 기다립니다."
        case (false, false): "진행 중인 작업이 없습니다."
        }
    }
}
