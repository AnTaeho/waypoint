import Foundation

/// 통합 화면의 집계. 검색·도구 필터와 무관하게 보관되지 않은 프로젝트 전체를 센다.
public struct DashboardOverview {
    public let groups: [DashboardGroup]
    public let liveCount: Int
    public let stalledCount: Int
    public let liveProjectCount: Int
    public let nextCount: Int
    public let doneTodayCount: Int
    public let resumeCards: [Card]

    public init(projects: [Project], now: Date, calendar: Calendar = .current) {
        let visible = projects.filter { $0.archivedAt == nil }
        groups = DashboardQuery.groups(for: visible, now: now)
        let rows = groups.flatMap(\.rows)
        liveCount = rows.filter { $0.workState == .live }.count
        stalledCount = rows.filter { $0.workState == .stalled }.count
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
}
