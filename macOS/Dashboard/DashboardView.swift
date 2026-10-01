import SwiftData
import SwiftUI
import WaypointKit

/// PC 통합 화면. 집계 → 진행 작업·이어가기 → 프로젝트 현황.
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
        let stalled = rows.filter { $0.workState == .stalled }
        let notes = overview.resumeCards.filter { card in
            guard let query else { return true }
            return DashboardSearch.matches(card, query)
                || card.project.map { DashboardSearch.matches($0, query) } == true
        }
        let items = DashboardSearch.filter(projects, query: query)
            .map { ProjectTableItem(project: $0, summary: DashboardQuery.summary(for: $0, now: now)) }
            .sorted {
                let a = $0.summary.lastActivityAt ?? .distantPast
                let b = $1.summary.lastActivityAt ?? .distantPast
                return a == b ? $0.project.key < $1.project.key : a > b
            }
        return GeometryReader { proxy in
            let width = max(0, proxy.size.width - Theme.Spacing.pageH * 2)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    heading(overview)
                    IntegrationStatusButton(compact: false)
                    DashboardStats(overview: overview)
                    if width >= Theme.Dashboard.twoColumnWidth {
                        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                            DashboardWorkList(rows: live, now: now, provider: $provider)
                                .frame(maxWidth: .infinity)
                            DashboardContinue(rows: stalled, cards: notes, now: now)
                                .frame(width: Theme.Dashboard.contextWidth)
                        }
                    } else {
                        DashboardWorkList(rows: live, now: now, provider: $provider)
                        DashboardContinue(rows: stalled, cards: notes, now: now)
                    }
                    DashboardProjects(items: items, now: now, select: selectProject)
                }
                .padding(.horizontal, Theme.Spacing.pageH)
                .padding(.vertical, Theme.Spacing.pageV)
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
    }

    private func heading(_ overview: DashboardOverview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("지금, 프로젝트들은 어디쯤일까")
                .font(Theme.pageTitle).foregroundStyle(Theme.text)
            Text(overview.liveProjectCount > 0
                 ? "\(overview.liveProjectCount)개 프로젝트에서 작업 중입니다."
                 : "진행 중인 작업이 없습니다.")
                .font(Theme.body).foregroundStyle(Theme.textMuted)
        }
    }
}
