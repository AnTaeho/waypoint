import SwiftUI
import WaypointKit

/// 카드 인스펙터의 「GitHub」 구역: 이 카드의 이슈·PR과 새로 여는 버튼.
struct GitHubSection: View {
    let card: Card
    @Environment(AppServices.self) private var services: AppServices?
    @State private var opening: GitHubKind?

    var body: some View {
        let recorded = GitHubLog.items(for: card)
        let items = services?.github.shown(recorded) ?? recorded
        let canOpen = canOpen
        // 붙일 뷰가 늘 있도록 판정은 body에서 바로 하고, 나머지는 구역 자체에 붙인다
        if canOpen || !items.isEmpty {
            InspectorSection("GitHub") {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(items) { GitHubItemRow(item: $0) }
                    if canOpen {
                        HStack(spacing: Theme.Spacing.s) {
                            Button("이슈 열기…") { opening = .issue }
                            Button("PR 열기…") { opening = .pr }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .task(id: card.id) {
                services?.github.refreshIfStale(recorded)
                #if DEBUG
                if canOpen, let kind = GitHubLaunch.sheet { opening = kind }
                #endif
            }
            .onChange(of: recorded.map(\.key)) { services?.github.refreshIfStale(recorded) }
            .sheet(item: $opening) { kind in
                GitHubOpenSheet(card: card, kind: kind)
            }
        }
    }

    /// 이 프로젝트 폴더가 GitHub 저장소에 이어져 있는가(`.git/config`만 읽는다)
    private var canOpen: Bool {
        guard services != nil, let root = card.project?.rootPath else { return false }
        return (try? GitHubRepo.read(rootPath: root)) != nil
    }
}

extension GitHubKind: @retroactive Identifiable {
    public var id: String { rawValue }
}
