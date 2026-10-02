import Foundation
import SwiftData

/// 대시보드 상황판의 프로젝트 타일 하나(TRK-64). 지금 상황 글, 진행 중·다음·최근 끝낸 카드, 정리 안 된 작업·아이디어 수.
/// 카드 선택은 보드와 같은 규칙(`BoardQuery.columns`)을 쓰고, 작업중 판정은 대시보드 줄(`DashboardQuery.rows`)을 쓴다.
public struct ProjectSituation: Identifiable {
    /// 섹션마다 보이는 최대 카드 수
    public static let itemLimit = 3

    /// 진행 중 카드 한 줄. 같은 카드에 세션이 여럿이면 한 줄로 모은다.
    public struct WorkItem: Identifiable {
        public let card: Card
        /// 붙은 세션 중 하나라도 live면 live, 아니면 stalled
        public let workState: CardWorkState
        /// 붙은 세션의 도구(중복 없이, 처음 나온 순서)
        public let providers: [AgentProvider]
        /// 붙은 세션이 다른 작업과 같이 만지는 파일 수(TRK-17, 합집합). 없으면 0
        public var overlapFileCount: Int = 0

        public var id: UUID { card.id }
    }

    public let project: Project
    /// 카드 없는 세션까지 포함해 live 줄이 하나라도 있는가(타일 머리의 작업중 점)
    public let isLive: Bool
    public let lastActivityAt: Date?
    /// 최신 지금 상황. 없으면 nil
    public let status: ProjectStatus.Entry?
    /// 진행 중 카드, 대시보드 줄 순서(세션 시작순) 최대 `itemLimit`
    public let inProgress: [WorkItem]
    public let inProgressCount: Int
    /// 다음 할 일, 번호순 최대 `itemLimit`
    public let next: [Card]
    public let nextCount: Int
    /// 최근 7일 안에 끝낸 카드(`BoardQuery.doneWindow`), 끝낸 시각 최신순 최대 `itemLimit`
    public let recentDone: [Card]
    public let recentDoneCount: Int
    public let unfiledCount: Int
    public let ideaCount: Int

    public var id: UUID { project.id }

    /// 타일 하나를 만든다.
    /// - provider: 주면 진행 중 카드는 그 도구 세션이 붙은 것만, 작업중 점도 그 도구 줄로만 본다.
    /// - cardFilter: 주면 카드 섹션(진행 중·다음·최근 끝냄)에 맞는 카드만 남긴다(검색). 개수도 거른 뒤 센다.
    public static func make(
        for project: Project,
        now: Date,
        status: ProjectStatus.Entry?,
        unfiledCount: Int,
        provider: AgentProvider? = nil,
        cardFilter: ((Card) -> Bool)? = nil,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> ProjectSituation {
        let keep = cardFilter ?? { _ in true }
        let rows = DashboardQuery.rows(for: project, now: now, stallTimeout: stallTimeout)
            .filter { provider == nil || $0.session.provider == provider }

        var order: [UUID] = []
        var grouped: [UUID: (card: Card, live: Bool, providers: [AgentProvider], overlaps: Set<String>)] = [:]
        let overlaps = rows.contains { $0.card != nil }
            ? WorkOverlap.index(for: project, now: now, stallTimeout: stallTimeout) : .empty
        for row in rows {
            guard let card = row.card, keep(card) else { continue }
            var entry = grouped[card.id] ?? (card, false, [], [])
            if grouped[card.id] == nil { order.append(card.id) }
            entry.live = entry.live || row.workState == .live
            if !entry.providers.contains(row.session.provider) { entry.providers.append(row.session.provider) }
            if !overlaps.isEmpty { entry.overlaps.formUnion(overlaps.overlaps(for: row.session).flatMap(\.files)) }
            grouped[card.id] = entry
        }
        let work = order.compactMap { grouped[$0] }.map {
            WorkItem(card: $0.card, workState: $0.live ? .live : .stalled, providers: $0.providers,
                     overlapFileCount: $0.overlaps.count)
        }

        let columns = BoardQuery.columns(for: project, now: now)
        let next = (columns[.next] ?? []).map(\.card).filter(keep)
        let done = (columns[.done] ?? []).map(\.card).filter(keep)
        let ideas = (project.cards ?? []).filter { $0.status == .idea }.count

        return ProjectSituation(
            project: project,
            isLive: rows.contains { $0.workState == .live },
            lastActivityAt: DashboardQuery.lastActivityAt(of: project),
            status: status,
            inProgress: Array(work.prefix(itemLimit)),
            inProgressCount: work.count,
            next: Array(next.prefix(itemLimit)),
            nextCount: next.count,
            recentDone: Array(done.prefix(itemLimit)),
            recentDoneCount: done.count,
            unfiledCount: unfiledCount,
            ideaCount: ideas
        )
    }

    /// 상황판 전체. 보관된 프로젝트는 뺀다. 순서: 작업 중인 프로젝트 먼저, 그다음 마지막 활동 최근순, 같으면 키순.
    /// 지금 상황은 한 번에 읽고(`ProjectStatus.latestEntries`), 정리 안 된 작업은 개수만 센다(`UnfiledWork.count`).
    /// - cardFilter: 프로젝트마다 카드 거르기(nil이면 그 프로젝트는 거르지 않는다).
    public static func board(
        for projects: [Project],
        now: Date,
        provider: AgentProvider? = nil,
        cardFilter: (Project) -> ((Card) -> Bool)? = { _ in nil },
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> [ProjectSituation] {
        let visible = projects.filter { $0.archivedAt == nil }
        let statuses = visible.first?.modelContext.map(ProjectStatus.latestEntries(in:))
        let tiles = visible.map { project in
            make(
                for: project, now: now,
                status: statuses.map { $0[project.id] } ?? ProjectStatus.latest(for: project),
                unfiledCount: UnfiledWork.count(for: project, now: now),
                provider: provider, cardFilter: cardFilter(project), stallTimeout: stallTimeout
            )
        }
        return tiles.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            let at = a.lastActivityAt ?? .distantPast, bt = b.lastActivityAt ?? .distantPast
            if at != bt { return at > bt }
            return a.project.key < b.project.key
        }
    }
}
