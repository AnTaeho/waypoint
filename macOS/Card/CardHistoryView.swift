import SwiftUI
import WaypointKit

/// 히스토리: 이 카드의 기록을 최신순으로, 왼쪽 세로선 위에 점을 찍어 보인다.
struct CardHistoryView: View {
    let lines: [HistoryLine]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("히스토리")
                .font(Theme.sectionLarge)
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HistoryRow(line: line, now: now, isLast: index == lines.count - 1)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let line: HistoryLine
    let now: Date
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            // 점 아래로 다음 줄까지 이어지는 세로선
            marker
                .padding(.top, Theme.Spacing.xs + 1)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(alignment: .top) {
                    if !isLast {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: Theme.Size.liveBorder)
                            .padding(.top, Theme.Spacing.xs + 1 + Theme.Size.dot)
                    }
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs + 1) {
                headline
                    .font(Theme.detailBody)
                    .foregroundStyle(Theme.text)
                Text(caption)
                    .font(Theme.captionLarge)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.l + 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var headline: Text {
        guard let code = line.code else { return Text(line.text) }
        return Text(code).font(Theme.mono) + Text(" ") + Text(line.text)
    }

    private var caption: String {
        let time = TimeFormat.timestamp(line.at, now: now)
        return line.session.map { "\(time) · \($0)" } ?? time
    }

    @ViewBuilder private var marker: some View {
        switch line.marker {
        case .active: FilledDot(color: Theme.live)
        case .next: FilledDot(color: Theme.next)
        case .done: FilledDot(color: Theme.done)
        case .idea: IdeaDot()
        case .file, .commit, .neutral: FilledDot(color: Theme.ideaBorder)
        case .note: FilledDot(color: Theme.textMuted)
        }
    }
}
