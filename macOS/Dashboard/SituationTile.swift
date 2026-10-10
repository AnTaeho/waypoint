import SwiftUI
import WaypointKit

/// 상황판 타일 하나. 머리를 누르면 프로젝트 보드, 카드 줄을 누르면 카드 상세.
struct SituationTile: View {
    let tile: ProjectSituation
    let now: Date
    /// 이 프로젝트에서 연 이슈·PR(확인한 상태를 입힌 것)
    var github: [GitHubItem] = []
    let select: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Situation.sectionGap) {
            head
            if !tile.waiting.isEmpty { SituationWaitingRow(waiting: tile.waiting) }
            if let status = tile.status {
                SituationStatus(entry: status, now: now)
            }
            if !tile.inProgress.isEmpty {
                SituationSection(title: "진행 중", count: tile.inProgressCount) {
                    ForEach(tile.inProgress) { item in SituationWorkRow(item: item, now: now) }
                }
            }
            if !tile.next.isEmpty {
                SituationSection(title: "다음", count: tile.nextCount) {
                    ForEach(tile.next) { card in SituationCardRow(card: card) }
                }
            }
            if !tile.recentDone.isEmpty {
                SituationSection(title: "최근 끝냄", count: tile.recentDoneCount) {
                    ForEach(tile.recentDone) { card in
                        SituationCardRow(card: card, trailing: card.doneAt.map { TimeFormat.relative($0, now: now) })
                    }
                }
            }
            footer
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
        }
    }

    private var head: some View {
        Button { select(tile.project) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text(tile.project.key).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                Text(tile.project.name).font(Theme.cardTitle).foregroundStyle(Theme.text).lineLimit(1)
                if tile.isLive { LiveDot().alignmentGuide(.firstTextBaseline) { $0[.bottom] } }
                Spacer(minLength: Theme.Spacing.s)
                if let at = tile.lastActivityAt {
                    Text(TimeFormat.relative(at, now: now))
                        .font(Theme.Situation.meta).foregroundStyle(Theme.textMuted).fixedSize()
                }
                Image(systemName: "chevron.right").font(Theme.caption).foregroundStyle(Theme.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tile.project.rootPath)
    }

    @ViewBuilder private var footer: some View {
        let open = GitHubLog.openSummary(github)
        if tile.unfiledCount > 0 || tile.ideaCount > 0 || open != nil {
            HStack(spacing: Theme.Spacing.m) {
                if tile.unfiledCount > 0 {
                    Text("정리 안 된 작업 \(tile.unfiledCount)")
                        .font(Theme.captionLargeMedium).foregroundStyle(Theme.liveText)
                }
                if tile.ideaCount > 0 {
                    Text("아이디어 \(tile.ideaCount)").font(Theme.Situation.meta).foregroundStyle(Theme.textMuted)
                }
                if let open {
                    Label(open, systemImage: Theme.GitHub.prIcon).font(Theme.Situation.meta).foregroundStyle(Theme.textMuted)
                }
            }
            .monospacedDigit()
        }
    }
}
