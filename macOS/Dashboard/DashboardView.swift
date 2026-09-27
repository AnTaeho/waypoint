import SwiftData
import SwiftUI
import WaypointKit

/// 대시보드 본문: 상황 제목, 작업중 표, 프로젝트 표.
struct DashboardView: View {
    let searchText: String
    let selectProject: (Project) -> Void

    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }, sort: \Project.name)
    private var projects: [Project]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date)
        }
        .background(Theme.bg)
    }

    private func content(now: Date) -> some View {
        let groups = DashboardQuery.groups(for: projects, now: now)
        let liveCount = groups.reduce(0) { $0 + $1.rows.filter { $0.workState == .live }.count }
        let query = DashboardSearch.normalized(searchText)
        let sections = DashboardSearch.sections(groups, query: query)
        let summaries = projects.map { ($0, DashboardQuery.summary(for: $0, now: now)) }
        let shownProjects = Set(DashboardSearch.filter(projects, query: query).map(\.persistentModelID))
        let projectRows = summaries
            .filter { shownProjects.contains($0.0.persistentModelID) }
            .sorted { ($0.1.lastActivityAt ?? .distantPast) > ($1.1.lastActivityAt ?? .distantPast) }
            .map { ProjectTableItem(project: $0.0, summary: $0.1) }

        // GeometryReader로 감싸 표의 최소 폭이 분할 뷰로 번지지 않게 한다(사이드바·인스펙터가 눌려 잘리는 문제).
        return GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    Text(liveCount > 0 ? "작업 \(liveCount)개 진행 중" : "진행 중인 작업 없음")
                        .font(Theme.pageTitle)
                        .foregroundStyle(Theme.text)
                    if !sections.isEmpty {
                        ActiveWorkTable(sections: sections, now: now)
                    }
                    if !projectRows.isEmpty {
                        ProjectTable(items: projectRows, now: now, select: selectProject)
                    }
                }
                .padding(.horizontal, Theme.Spacing.pageH)
                .padding(.vertical, Theme.Spacing.pageV)
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
    }
}
