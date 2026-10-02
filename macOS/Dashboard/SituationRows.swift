import SwiftUI
import WaypointKit

/// 타일 안 구역: 작은 머리(이름 · 전체 수) + 줄들.
struct SituationSection<Rows: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Situation.rowGap) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                Text("\(count)").monospacedDigit()
            }
            .font(Theme.Situation.sectionTitle).foregroundStyle(Theme.textMuted)
            rows()
        }
    }
}

/// 카드 한 줄: ID · 제목 · 오른쪽 덧붙임. 누르면 카드 상세.
struct SituationCardRow<Leading: View>: View {
    let card: Card
    var trailing: String?
    var muted = false
    /// 제목 뒤 작은 강조 표시(같은 파일 작업 중)
    var flag: String?
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        NavigationLink(value: card) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                leading()
                Text(card.displayID).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                    .lineLimit(1).frame(width: Theme.Situation.idWidth, alignment: .leading)
                Text(card.title).font(Theme.Situation.rowTitle)
                    .foregroundStyle(muted ? Theme.textSecondary : Theme.text)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Theme.Spacing.s)
                if let flag {
                    Text(flag).font(Theme.Situation.meta).foregroundStyle(Theme.Overlap.text).fixedSize()
                }
                if let trailing {
                    Text(trailing).font(Theme.Situation.meta).foregroundStyle(Theme.textMuted).fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(card.title)
    }
}

extension SituationCardRow where Leading == EmptyView {
    init(card: Card, trailing: String? = nil) {
        self.init(card: card, trailing: trailing, muted: false, flag: nil) { EmptyView() }
    }
}

/// 진행 중 카드 줄: 상태 점 + 카드 줄 + 도구(멈추면 「멈춤」).
struct SituationWorkRow: View {
    let item: ProjectSituation.WorkItem

    var body: some View {
        SituationCardRow(card: item.card, trailing: trailing, muted: item.workState != .live,
                         flag: item.overlapFileCount > 0 ? "같은 파일 \(item.overlapFileCount)" : nil) {
            WorkStateDot(state: item.workState)
        }
    }

    private var trailing: String {
        let tools = item.providers.map(\.name).joined(separator: " · ")
        return item.workState == .live ? tools : "멈춤 · \(tools)"
    }
}
