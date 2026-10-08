import SwiftData
import SwiftUI
import WaypointKit

/// 손 없이 화면을 확인할 때만 쓰는 실행 인자(Debug만, TRK-68). Release에서는 모두 꺼져 있다.
/// - `-WaypointProject PRB`: 그 프로젝트 보드에서 시작한다.
/// - `-WaypointGitHub list`: 보드 머리의 이슈·PR 목록을 시트로 연다(숨긴 채 띄운 앱은 팝오버가 뜨지 않는다).
///   `issue`·`pr`: 카드 인스펙터에서 그 열기 시트를 연다.
enum GitHubLaunch {
    #if DEBUG
    private static var mode: String? { UserDefaults.standard.string(forKey: "WaypointGitHub") }
    static var list: Bool { mode == "list" }
    static var sheet: GitHubKind? { mode.flatMap(GitHubKind.init(rawValue:)) }
    static var projectKey: String? { UserDefaults.standard.string(forKey: "WaypointProject") }
    #else
    static let list = false
    static let sheet: GitHubKind? = nil
    static let projectKey: String? = nil
    #endif
}

extension View {
    func projectLaunch(selection: Binding<SidebarSelection?>) -> some View {
        modifier(ProjectLaunch(selection: selection))
    }
}

private struct ProjectLaunch: ViewModifier {
    @Binding var selection: SidebarSelection?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.onAppear {
            guard let key = GitHubLaunch.projectKey, selection == .dashboard else { return }
            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            if let project = projects.first(where: { $0.key == key }) { selection = .project(project.persistentModelID) }
        }
    }
}
