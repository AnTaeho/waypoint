import SwiftUI
import WaypointKit

struct DashboardProjects: View {
    let items: [ProjectTableItem]
    let now: Date
    let select: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Divider()
            HStack(spacing: Theme.Spacing.s) {
                Text("프로젝트").font(Theme.sectionLarge)
                Text("\(items.count)").font(Theme.caption).foregroundStyle(Theme.textMuted)
                Spacer()
                Text("최근 활동순").font(Theme.caption).foregroundStyle(Theme.textMuted)
            }.padding(.top, Theme.Spacing.m)
            if items.isEmpty { DashboardEmpty(message: "표시할 프로젝트가 없습니다.") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.Dashboard.projectMinWidth))],
                      alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(items) { item in
                    Button { select(item.project) } label: {
                        DashboardProjectTile(item: item, now: now)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DashboardProjectTile: View {
    let item: ProjectTableItem
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text(item.project.key).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                Spacer()
                Image(systemName: "arrow.right").font(Theme.caption).foregroundStyle(Theme.textMuted)
            }
            Text(item.project.name).font(Theme.cardTitle).foregroundStyle(Theme.text).lineLimit(1)
            Text(item.project.summary.isEmpty ? "프로젝트 보드 보기" : item.project.summary)
                .font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
                .lineLimit(2).frame(height: Theme.Dashboard.summaryHeight, alignment: .top)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.m) { counts }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { counts }
            }.font(Theme.caption)
            Text(item.project.rootPath).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                .lineLimit(1).truncationMode(.middle).help(item.project.rootPath)
            Text(item.summary.lastActivityAt.map { TimeFormat.relative($0, now: now) } ?? "활동 없음")
                .font(Theme.caption).foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
        }
    }

    @ViewBuilder private var counts: some View {
        Text("작업 중 \(item.summary.liveCount)")
            .foregroundStyle(item.summary.liveCount > 0 ? Theme.liveText : Theme.textMuted)
        if item.summary.stalledCount > 0 {
            Text("대기 \(item.summary.stalledCount)").foregroundStyle(Theme.textMuted)
        }
        Text("다음 \(item.summary.nextCount)").foregroundStyle(Theme.textMuted)
        Text("아이디어 \(item.summary.ideaCount)").foregroundStyle(Theme.textMuted)
    }
}
