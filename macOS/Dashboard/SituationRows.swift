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

/// 나를 기다리는 세션: 「승인 기다림 1」「질문 기다림 1」 알약을 나란히.
struct SituationWaitingRow: View {
    let waiting: SessionWaiting

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(waiting.labels, id: \.self) { label in
                Text(label)
                    .font(Theme.Situation.waitingFont).foregroundStyle(Theme.Situation.waitingText)
                    .monospacedDigit().lineLimit(1).fixedSize()
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.Situation.waitingBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            }
        }
    }
}

/// 카드 한 줄: ID · 제목 · 오른쪽 덧붙임. 누르면 카드 상세.
struct SituationCardRow<Leading: View>: View {
    let card: Card
    var trailing: String?
    /// 오른쪽 덧붙임이 내 답을 기다린다는 글이면 강조색
    var trailingWaits = false
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
                    Text(trailing).font(Theme.Situation.meta)
                        .foregroundStyle(trailingWaits ? Theme.Situation.waitingText : Theme.textMuted).fixedSize()
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
        self.init(card: card, trailing: trailing, trailingWaits: false, muted: false, flag: nil) { EmptyView() }
    }
}

/// 진행 중 카드 줄: 상태 점 + 카드 줄 + 도구(멈추면 「멈춤」, 내 답을 기다리면 「승인 대기 3분」).
struct SituationWorkRow: View {
    let item: ProjectSituation.WorkItem
    let now: Date

    var body: some View {
        SituationCardRow(card: item.card, trailing: trailing, trailingWaits: item.waiting != nil,
                         muted: item.workState != .live,
                         flag: item.overlapFileCount > 0 ? "같은 파일 \(item.overlapFileCount)" : nil) {
            WorkStateDot(state: item.workState)
        }
    }

    private var trailing: String {
        if let waiting = item.waiting { return waiting.text(now: now) }
        let tools = item.providers.map(\.name).joined(separator: " · ")
        return item.workState == .live ? tools : "멈춤 · \(tools)"
    }
}
