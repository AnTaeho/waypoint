import SwiftUI
import WaypointKit

/// 프로젝트 보드 머리의 「이슈 N · PR N」(열린 수). 누르면 이 프로젝트에서 연 것 전부를 보인다.
struct GitHubBoardButton: View {
    let project: Project
    @Environment(AppServices.self) private var services: AppServices?
    @State private var showsList = false
    /// 숨긴 채 띄운 앱은 팝오버가 뜨지 않아, 확인용 실행 인자는 같은 목록을 시트로 보인다(Debug만)
    @State private var showsListSheet = false

    var body: some View {
        let recorded = GitHubLog.items(for: project)
        let items = services?.github.shown(recorded) ?? recorded
        if !items.isEmpty {
            Button {
                showsList = true
            } label: {
                Label(GitHubLog.openSummary(items) ?? "이슈 0 · PR 0", systemImage: Theme.GitHub.prIcon)
                    .font(Theme.captionLargeMedium).monospacedDigit()
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showsList, arrowEdge: .bottom) {
                GitHubItemList(items: items)
                    .onAppear { services?.github.refreshIfStale(recorded) }
            }
            .task(id: project.id) {
                #if DEBUG
                if GitHubLaunch.list {
                    try? await Task.sleep(for: .milliseconds(900))
                    showsListSheet = true
                }
                #endif
            }
            .sheet(isPresented: $showsListSheet) { GitHubItemList(items: items) }
        }
    }
}

/// 팝오버 안 목록: 열린 것 먼저, 그다음 최근순.
private struct GitHubItemList: View {
    let items: [GitHubItem]

    var body: some View {
        let ordered = items.filter(\.state.isOpen) + items.filter { !$0.state.isOpen }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.rowH) {
                ForEach(ordered) { GitHubItemRow(item: $0, showsCard: true) }
            }
            .padding(Theme.Spacing.l)
        }
        .frame(width: Theme.GitHub.popoverWidth)
        .frame(maxHeight: Theme.GitHub.popoverMaxHeight)
        .background(Theme.bg)
    }
}
