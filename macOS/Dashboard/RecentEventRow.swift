import SwiftUI
import WaypointKit

/// 최근 기록 한 줄: 표시 점, 카드 ID(모노)와 문구, 아래 줄 상대 시각.
struct RecentEventRow: View {
    let line: RecentEventLine
    let now: Date
    let showsDivider: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            marker
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                headline
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(caption)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, Theme.Spacing.m - 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
    }

    private var headline: Text {
        guard let subject = line.subject else { return Text(line.text) }
        let head = line.subjectIsCardID
            ? Text(subject).font(Theme.mono)
            : Text(subject).foregroundColor(Theme.textSecondary)
        return head + Text(" ") + Text(line.text)
    }

    private var caption: String {
        let time = TimeFormat.relative(line.at, now: now)
        return line.detail.map { "\(time) · \($0)" } ?? time
    }

    @ViewBuilder private var marker: some View {
        switch line.marker {
        case .active: FilledDot(color: Theme.live)
        case .done: FilledDot(color: Theme.done)
        case .next: FilledDot(color: Theme.next)
        case .commit: FilledDot(color: Theme.ideaBorder)
        case .idea: IdeaDot()
        case .guide:
            Image(systemName: "doc")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.Size.dot)
        }
    }
}
