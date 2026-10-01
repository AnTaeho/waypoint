import SwiftData
import SwiftUI
import WaypointKit

/// 사이드바 선택에 맞는 첫 화면.
struct DetailRootView: View {
    let selection: SidebarSelection
    let mode: ProjectMode
    @Binding var guideDocID: PersistentIdentifier?
    let searchText: String
    let selectProject: (Project) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        switch selection {
        case .dashboard:
            DashboardView(searchText: searchText, selectProject: selectProject)
                .navigationTitle("대시보드")
        case .guidance:
            GuidanceView(searchText: searchText)
        case .project(let id):
            if let project = context.model(for: id) as? Project {
                switch mode {
                case .board: ProjectBoardView(project: project)
                case .guide: GuideView(project: project, selectedID: $guideDocID)
                case .activity: ProjectActivityView(project: project, searchText: searchText).id(project.id)
                }
            } else {
                Theme.bg.navigationTitle("")
            }
        }
    }
}
