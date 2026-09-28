import SwiftData
import SwiftUI
import WaypointKit

/// macOS 창 틀: 사이드바 | 본문(NavigationStack) + 오른쪽 인스펙터.
struct RootView: View {
    @State private var selection: SidebarSelection? = .dashboard
    /// 본문 스택. 쌓이는 화면은 카드 상세뿐이라 카드 배열로 들고, 맨 위 카드를 인스펙터에 보인다.
    @State private var path: [Card] = []
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
        }
        .inspector(isPresented: $showsInspector) {
            inspector
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
                    Label(inspectorTitle, systemImage: "sidebar.right")
                }
                .help(inspectorTitle)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "검색")
        .frame(minWidth: Theme.Size.windowMinWidth, minHeight: Theme.Size.windowMinHeight)
        .onChange(of: selection) {
            path = []
        }
    }

    /// 카드 상세가 맨 위면 카드 정보, 아니면 최근 기록.
    @ViewBuilder private var inspector: some View {
        if let card = path.last {
            CardInspector(card: card) { path.append($0) }
        } else {
            RecentEventsInspector(projectID: selectedProjectID)
        }
    }

    private var inspectorTitle: String { path.isEmpty ? "최근 기록" : "카드 정보" }

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
