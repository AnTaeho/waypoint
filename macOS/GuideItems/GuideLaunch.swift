import SwiftData
import SwiftUI
import WaypointKit

/// 손 없이 화면을 확인할 때만 쓰는 실행 인자(Debug만). Release에서는 모두 꺼져 있다.
/// - `-WaypointGuideMode items`: 지침 문서를 항목 보기로 연다. 지침 화면(`-WaypointSidebar guidance`)도 항목으로,
///   그 밖이면 지침 문서가 있는 첫 프로젝트의 지침 문서 화면을 고른다.
/// - `-WaypointGuideItemsEdit 2`: 항목 보기를 열 때 그 순번(0부터, 하위 포함) 항목의 편집 상자를 연다.
enum GuideLaunch {
    #if DEBUG
    static var items: Bool { UserDefaults.standard.string(forKey: "WaypointGuideMode") == "items" }
    static var editIndex: Int? {
        UserDefaults.standard.object(forKey: "WaypointGuideItemsEdit") == nil
            ? nil : UserDefaults.standard.integer(forKey: "WaypointGuideItemsEdit")
    }
    #else
    static let items = false
    static let editIndex: Int? = nil
    #endif

    static var guideMode: GuideMode { items ? .items : .read }
}

extension View {
    /// `-WaypointGuideMode items`이고 대시보드에서 시작하면 지침 문서가 있는 첫 프로젝트의 지침 문서 화면으로.
    func guideLaunch(selection: Binding<SidebarSelection?>, projectMode: Binding<ProjectMode>) -> some View {
        modifier(GuideLaunchModifier(selection: selection, projectMode: projectMode))
    }
}

private struct GuideLaunchModifier: ViewModifier {
    @Binding var selection: SidebarSelection?
    @Binding var projectMode: ProjectMode
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.onAppear {
            guard GuideLaunch.items, selection == .dashboard else { return }
            let projects = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)]))) ?? []
            guard let project = projects.first(where: { !($0.guideDocs ?? []).isEmpty }) else { return }
            projectMode = .guide
            selection = .project(project.persistentModelID)
        }
    }
}
