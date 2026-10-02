import SwiftData
import SwiftUI
import WaypointKit

/// macOS 창 틀: 사이드바 | 본문(NavigationStack) + 오른쪽 인스펙터.
struct RootView: View {
    @State private var selection: SidebarSelection? = RootView.launchSelection
    /// 본문 스택. 쌓이는 화면은 카드 상세뿐이라 카드 배열로 들고, 맨 위 카드를 인스펙터에 보인다.
    @State private var path: [Card] = []
    /// 프로젝트를 골랐을 때 보드와 지침 문서 중 무엇을 보나. 프로젝트를 바꿔도 유지한다.
    @State private var projectMode: ProjectMode = .board
    /// 지침 문서 화면에서 고른 문서. 프로젝트를 바꾸면 비운다(첫 문서).
    @State private var guideDocID: PersistentIdentifier?
    @State private var showsInspector = true
    @State private var showsDashboardInspector = false
    /// 프로젝트 보드 화면의 인스펙터. 네 칸이 넓게 보이도록 닫힌 채 시작하고, 연 뒤에는 앱을 끌 때까지 기억한다.
    @State private var showsBoardInspector = false
    @State private var showsActivityInspector = false
    @State private var searchText = ""
    /// 샘플 모드에서는 nil
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(\.openWindow) private var openWindow

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
                DetailRootView(
                    selection: selection ?? .dashboard,
                    mode: projectMode,
                    guideDocID: $guideDocID,
                    searchText: searchText
                ) { project in
                    selection = .project(project.persistentModelID)
                }
                .navigationDestination(for: Card.self) { card in
                    CardDetailView(card: card)
                }
            }
        }
        .inspector(isPresented: inspectorShown) {
            RootInspector(
                projectID: selectedProjectID,
                card: path.last,
                guideDocID: projectMode == .guide ? guideDocID : nil,
                open: { path.append($0) }
            )
            .inspectorColumnWidth(
                min: Theme.Size.inspectorMinWidth,
                ideal: Theme.Size.inspectorWidth,
                max: Theme.Size.inspectorMaxWidth
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { IntegrationStatusButton() }
            if #available(macOS 26.0, *) {
                // 서로 다른 기능의 버튼을 하나의 유리 배경으로 묶지 않는다.
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            if selectedProjectID != nil, path.isEmpty {
                ToolbarItem(placement: .principal) {
                    Picker("화면", selection: $projectMode) {
                        Text("보드").tag(ProjectMode.board)
                        Text("활동").tag(ProjectMode.activity)
                        Text("지침 문서").tag(ProjectMode.guide)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorShown.wrappedValue.toggle()
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
            guideDocID = nil
        }
        .onChange(of: projectMode) {
            path = []
        }
        .onChange(of: services?.pendingSelection, initial: true) { _, id in
            guard let id else { return }
            selection = .project(id)
            services?.pendingSelection = nil
        }
        .onAppear {
            services?.mainWindowCount += 1
            services?.openMainWindow = { [openWindow] in openWindow(id: WaypointApp.mainWindowID) }
        }
        .onDisappear { services?.mainWindowCount -= 1 }
        .guideLaunch(selection: $selection, projectMode: $projectMode)
        .onboardingSheet(services)
        .settingsLaunch()
    }

    private var inspectorTitle: String {
        if !path.isEmpty { return "카드 정보" }
        return projectMode == .guide && selectedProjectID != nil ? "문서 정보" : "최근 기록"
    }

    /// 보드 화면이면 보드 전용 상태, 대시보드·카드 상세·지침 문서는 공용 상태.
    private var inspectorShown: Binding<Bool> {
        let isBoard = selectedProjectID != nil && projectMode == .board && path.isEmpty
        if selectedProjectID == nil && path.isEmpty { return $showsDashboardInspector }
        if selectedProjectID != nil && projectMode == .activity && path.isEmpty { return $showsActivityInspector }
        return isBoard ? $showsBoardInspector : $showsInspector
    }

    private var selectedProjectID: PersistentIdentifier? {
        if case .project(let id) = selection { id } else { nil }
    }
}

extension RootView {
    #if DEBUG
    /// 손 없이 화면을 확인할 때만: 실행 인자 `-WaypointSidebar guidance`로 지침 화면에서 시작한다(Debug만).
    static var launchSelection: SidebarSelection {
        UserDefaults.standard.string(forKey: "WaypointSidebar") == "guidance" ? .guidance : .dashboard
    }
    #else
    static let launchSelection: SidebarSelection = .dashboard
    #endif
}

/// 프로젝트 화면 종류.
enum ProjectMode: Hashable {
    case board, activity, guide
}
