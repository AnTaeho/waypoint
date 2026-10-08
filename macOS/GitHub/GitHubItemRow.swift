import AppKit
import SwiftUI
import WaypointKit

/// 이슈·PR 한 줄: 종류 그림, 번호, 제목, 상태 알약. 누르면 브라우저로 연다.
struct GitHubItemRow: View {
    let item: GitHubItem
    /// 프로젝트 목록에서는 이어진 카드도 보인다
    var showsCard = false

    var body: some View {
        Button {
            if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: Theme.GitHub.icon(item.kind))
                    .font(Theme.caption).foregroundStyle(Theme.textMuted)
                    .frame(width: Theme.GitHub.iconWidth)
                Text("#\(item.number)").font(Theme.GitHub.number).foregroundStyle(Theme.textMuted)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(item.title).font(Theme.body).foregroundStyle(Theme.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if showsCard, let card = item.cardID {
                        Text(card).font(Theme.monoCaption).foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                GitHubStatePill(state: item.state)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.url)
        .accessibilityLabel("\(item.label) \(item.title), \(item.state.label)")
    }
}

/// 상태 알약: 열림 / 닫힘 / 병합됨 / 초안.
struct GitHubStatePill: View {
    let state: GitHubState

    var body: some View {
        Text(state.label)
            .font(Theme.GitHub.pill)
            .foregroundStyle(Theme.GitHub.pillText(state))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs)
            .background { Capsule().fill(Theme.GitHub.pillFill(state)) }
            .overlay {
                if state == .draft { Capsule().strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
            }
            .fixedSize()
    }
}
