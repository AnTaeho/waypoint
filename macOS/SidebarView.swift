import SwiftData
import SwiftUI
import WaypointKit

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }, sort: \Project.name)
    private var projects: [Project]

    var body: some View {
        List(selection: $selection) {
            Label {
                Text("대시보드")
            } icon: {
                Image(systemName: "square.grid.2x2").foregroundStyle(Theme.liveText)
            }
            .tag(SidebarSelection.dashboard)

            Section("프로젝트") {
                ForEach(projects) { project in
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        SidebarProjectRow(project: project, now: timeline.date)
                    }
                    .tag(SidebarSelection.project(project.persistentModelID))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
    }
}

private struct SidebarProjectRow: View {
    let project: Project
    let now: Date

    var body: some View {
        let summary = DashboardQuery.summary(for: project, now: now)
        HStack(spacing: Theme.Spacing.s) {
            Text(project.key)
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textMuted)
                .frame(width: Theme.Size.sidebarKeyWidth, alignment: .leading)
            Text(project.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.liveCount > 0 {
                count(summary.liveCount) { LiveDot() }
            } else if summary.stalledCount > 0 {
                count(summary.stalledCount) { StalledDot() }
            }
        }
    }

    private func count(_ n: Int, @ViewBuilder dot: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            dot()
            Text("\(n)")
                .font(Theme.caption)
                .foregroundStyle(Theme.liveText)
                .monospacedDigit()
        }
    }
}
