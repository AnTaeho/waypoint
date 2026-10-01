import SwiftUI
import WaypointKit

/// 재개 창 위쪽 요약: 목표·남은 조건·미검증·메모를 한 묶음으로.
struct CardResumeSummaryView: View {
    let summary: CardResumeSummary
    private let limit = 5

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.m) {
            row("목표") {
                Text(summary.title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                if let goal = summary.goalLine {
                    Text(goal).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            row(summary.remaining.isEmpty ? "남은 조건" : "남은 조건 \(summary.remaining.count)") {
                items(summary.remaining, empty: "없음")
            }
            row(summary.unverified.isEmpty ? "미검증" : "미검증 \(summary.unverified.count)") {
                items(summary.unverified, empty: "없음")
            }
            row("메모") {
                if let freshness = summary.freshness {
                    Text(freshness.label).font(Theme.captionLarge)
                        .foregroundStyle(freshness.changedFileCount > 0 ? Theme.liveText : Theme.textMuted)
                }
                Text(summary.note ?? "없음").font(Theme.body)
                    .foregroundStyle(summary.note == nil ? Theme.textMuted : Theme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title).font(Theme.captionLargeMedium).foregroundStyle(Theme.textMuted)
                .frame(width: Theme.Resume.labelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { content() }
        }
    }

    @ViewBuilder private func items(_ list: [CardResumeSummary.Item], empty: String) -> some View {
        if list.isEmpty {
            Text(empty).font(Theme.body).foregroundStyle(Theme.textMuted)
        }
        ForEach(list.prefix(limit), id: \.number) { item in
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("\(item.number).").font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
                Text(item.text).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
                if let evidence = item.evidence {
                    Text(evidence).font(Theme.captionLarge).fixedSize()
                        .foregroundStyle(item.isFailure ? Theme.Evidence.fail : Theme.textMuted)
                }
            }
        }
        if list.count > limit {
            Text("외 \(list.count - limit)개").font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
        }
    }
}
