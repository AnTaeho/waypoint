import SwiftData
import SwiftUI
import WaypointKit

/// PC 통합 화면. 집계 → 진행 작업·이어가기 → 상황판(프로젝트 타일).
struct DashboardView: View {
    let searchText: String
    let selectProject: (Project) -> Void
    @State private var provider: AgentProvider?
    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }, sort: \Project.name)
    private var projects: [Project]

    var body: some View {
        LiveDataTimeline { now in
            content(now: now)
        }
        .background(Theme.bg)
    }

    private func content(now: Date) -> some View {
        let overview = DashboardOverview(projects: projects, now: now)
        let query = DashboardSearch.normalized(searchText)
        let sections = DashboardSearch.sections(overview.groups, query: query)
        let rows = sections.flatMap(\.rows).filter { provider == nil || $0.session.provider == provider }
        let live = rows.filter { $0.workState == .live }
        let overlaps = WorkOverlap.byRow(live, now: now)
        let held = DashboardOverview.split(rows)
        let notes = overview.resumeCards.filter { card in
            guard let query else { return true }
            return DashboardSearch.matches(card, query)
                || card.project.map { DashboardSearch.matches($0, query) } == true
        }
        let tiles = ProjectSituation.board(
            for: DashboardSearch.filter(projects, query: query), now: now, provider: provider,
            cardFilter: DashboardSearch.cardFilter(query)
        )
        return GeometryReader { proxy in
            let width = max(0, proxy.size.width - Theme.Spacing.pageH * 2)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        heading(overview)
                        IntegrationStatusButton(compact: false)
                        DashboardStats(overview: overview)
                        if width >= Theme.Dashboard.twoColumnWidth {
                            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                                DashboardWorkList(rows: live, now: now, provider: $provider, overlaps: overlaps)
                                    .frame(maxWidth: .infinity)
                                DashboardContinue(waiting: held.waiting, rows: held.resting, cards: notes, now: now)
                                    .frame(width: Theme.Dashboard.contextWidth)
                            }
                        } else {
                            DashboardWorkList(rows: live, now: now, provider: $provider, overlaps: overlaps)
                            DashboardContinue(waiting: held.waiting, rows: held.resting, cards: notes, now: now)
                        }
                        SituationBoard(tiles: tiles, width: width, now: now, select: selectProject)
                    }
                    .padding(.horizontal, Theme.Spacing.pageH)
                    .padding(.vertical, Theme.Spacing.pageV)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .dashboardScrollLaunch(reader)
            }
        }
    }

    private func heading(_ overview: DashboardOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("지금, 프로젝트들은 어디쯤일까")
                .font(Theme.pageTitle).foregroundStyle(Theme.text)
            Text(overview.headline)
                .font(Theme.body).foregroundStyle(Theme.textMuted)
        }
    }
}
