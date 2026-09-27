import SwiftData
import SwiftUI
import WaypointKit

/// macOS 창 틀: 사이드바 | 본문(NavigationStack) + 오른쪽 인스펙터.
struct RootView: View {
    @State private var selection: SidebarSelection? = .dashboard
    @State private var path = NavigationPath()
    @State private var showsInspector = true
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(
                    min: Theme.Size.sidebarMinWidth,
                    ideal: Theme.Size.sidebarWidth,
                    max: Theme.Size.sidebarMaxWidth
                )
        } detail: {
            NavigationStack(path: $path) {
                DetailRootView(selection: selection ?? .dashboard, searchText: searchText) { project in
                    selection = .project(project.persistentModelID)
                }
                .navigationDestination(for: Card.self) { card in
                    CardDetailView(card: card)
                }
            }
            .inspector(isPresented: $showsInspector) {
                RecentEventsInspector(projectID: selectedProjectID)
                    .inspectorColumnWidth(
                        min: Theme.Size.inspectorMinWidth,
                        ideal: Theme.Size.inspectorWidth,
                        max: Theme.Size.inspectorMaxWidth
                    )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsInspector.toggle()
                    } label: {
                        Label("최근 기록", systemImage: "sidebar.right")
                    }
                    .help("최근 기록")
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "검색")
        .frame(minWidth: Theme.Size.windowMinWidth, minHeight: Theme.Size.windowMinHeight)
        .onChange(of: selection) {
            path = NavigationPath()
        }
    }

    private var selectedProjectID: PersistentIdentifier? {
        if case .project(let id) = selection { id } else { nil }
    }
}

/// 사이드바 선택에 맞는 첫 화면.
private struct DetailRootView: View {
    let selection: SidebarSelection
    let searchText: String
    let selectProject: (Project) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        switch selection {
        case .dashboard:
            DashboardView(searchText: searchText, selectProject: selectProject)
                .navigationTitle("대시보드")
        case .project(let id):
            if let project = context.model(for: id) as? Project {
                ProjectBoardView(project: project)
            } else {
                Theme.bg.navigationTitle("")
            }
        }
    }
}
