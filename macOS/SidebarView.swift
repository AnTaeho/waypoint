import SwiftData
import SwiftUI
import WaypointKit

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }, sort: \Project.name)
    private var projects: [Project]
    @Query(filter: #Predicate<Project> { $0.archivedAt != nil }, sort: \Project.name)
    private var archived: [Project]
    @State private var showsArchived = false
    @State private var deleting: Project?
    @Environment(\.modelContext) private var context

    var body: some View {
        List(selection: $selection) {
            Label {
                Text("대시보드").font(Theme.body)
            } icon: {
                Image(systemName: "square.grid.2x2").foregroundStyle(Theme.liveText)
            }
            .tag(SidebarSelection.dashboard)

            Label {
                Text("지침").font(Theme.body)
            } icon: {
                Image(systemName: "text.book.closed").foregroundStyle(Theme.liveText)
            }
            .tag(SidebarSelection.guidance)

            Section {
                ForEach(projects) { project in
                    LiveDataTimeline { now in
                        SidebarProjectRow(project: project, now: now)
                    }
                    .tag(SidebarSelection.project(project.persistentModelID))
                    .contextMenu {
                        Button("보관") { archive(project) }
                        Divider()
                        Button("삭제…", role: .destructive) { deleting = project }
                    }
                }
            } header: {
                Text("프로젝트").font(Theme.tableHeader)
            }

            if !archived.isEmpty {
                Section(isExpanded: $showsArchived) {
                    ForEach(archived) { project in
                        SidebarArchivedRow(project: project)
                            .tag(SidebarSelection.project(project.persistentModelID))
                            .contextMenu {
                                Button("보관 해제") { try? ProjectRegistry.unarchive(project, context: context) }
                                Divider()
                                Button("삭제…", role: .destructive) { deleting = project }
                            }
                    }
                } header: {
                    Text("보관됨 \(archived.count)").font(Theme.tableHeader)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            DevBadge()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UsageGaugeView()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .projectDeleteAlert($deleting) { project in
            // 지운 프로젝트를 본문이 다시 읽지 않게 선택부터 옮긴다.
            if selection == .project(project.persistentModelID) { selection = .dashboard }
            try? ProjectRegistry.delete(project, context: context)
        }
    }

    private func archive(_ project: Project) {
        if selection == .project(project.persistentModelID) { selection = .dashboard }
        try? ProjectRegistry.archive(project, at: Date(), context: context)
    }
}

private struct SidebarProjectRow: View {
    let project: Project
    let now: Date
    /// 선택된 줄(파란 배경)에서는 고정 색 대신 계층 색을 써서 글자가 묻히지 않게 한다.
    @Environment(\.backgroundProminence) private var prominence

    private var isProminent: Bool { prominence == .increased }

    var body: some View {
        let summary = DashboardQuery.summary(for: project, now: now)
        HStack(spacing: Theme.Spacing.s) {
            SidebarKey(key: project.key)
            Text(project.name)
                .font(Theme.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.liveCount > 0 {
                count(summary.liveCount) { LiveDot() }
            } else if summary.stalledCount > 0 {
                // 내 답을 기다리는 세션이 있으면 점을 채운다.
                count(summary.stalledCount) {
                    if summary.waitingCount > 0 { FilledDot(color: Theme.Situation.waitingText) } else { StalledDot() }
                }
            }
        }
    }

    private func count(_ n: Int, @ViewBuilder dot: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            dot()
            Text("\(n)")
                .font(Theme.caption)
                .foregroundStyle(isProminent ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.liveText))
                .monospacedDigit()
        }
    }
}
