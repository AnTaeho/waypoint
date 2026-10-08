import SwiftUI
import WaypointKit

/// 대시보드 아래 상황판: 프로젝트 타일 격자. 본문 폭에 따라 1~3열.
struct SituationBoard: View {
    let tiles: [ProjectSituation]
    let width: CGFloat
    let now: Date
    let select: (Project) -> Void
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services: AppServices?

    static let scrollID = "situation-board"

    var body: some View {
        let recorded = GitHubLog.items(in: context)
        let github = Dictionary(grouping: services?.github.shown(recorded) ?? recorded, by: \.projectID)
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Divider()
            HStack(spacing: Theme.Spacing.s) {
                Text("프로젝트").font(Theme.sectionLarge)
                Text("\(tiles.count)").font(Theme.caption).foregroundStyle(Theme.textMuted)
            }.padding(.top, Theme.Spacing.m)
            if tiles.isEmpty { DashboardEmpty(message: "표시할 프로젝트가 없습니다.") }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(tiles) { tile in
                    SituationTile(tile: tile, now: now, github: github[tile.project.id] ?? [], select: select)
                }
            }
        }
        .id(Self.scrollID)
        .task { services?.github.refreshIfStale(recorded) }
    }

    private var columns: [GridItem] {
        let gap = Theme.Spacing.l
        let fit = Int((width + gap) / (Theme.Situation.tileMinWidth + gap))
        let count = min(max(fit, 1), Theme.Situation.maxColumns)
        return Array(repeating: GridItem(.flexible(), spacing: gap, alignment: .top), count: count)
    }
}
