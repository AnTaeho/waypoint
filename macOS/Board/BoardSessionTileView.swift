import SwiftUI
import WaypointKit

/// 작업중 칸의 카드 없는 세션 타일. 대시보드의 카드 없는 줄과 같은 정보(「카드 없음」·세션·최근 파일·경과)를
/// 흰 바탕 `border` 1pt로 카드보다 한 단 낮게 보인다. 끌거나 누를 수 없다.
struct BoardSessionTileView: View {
    let tile: BoardSessionTile
    let now: Date

    private var isLive: Bool { tile.workState == .live }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                WorkStateDot(state: tile.workState)
                Text("카드 없음")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                elapsed
                    .lineLimit(1)
            }
            sessionBox
        }
        .padding(Theme.Spacing.rowH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.card)
            shape.fill(Theme.surface)
                .overlay { shape.strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
        }
    }

    private var sessionBox: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs + 2) {
                Image(systemName: "terminal")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.text)
                Text(SessionFormat.label(for: tile.session))
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if tile.runningSubagents > 0 {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(Theme.caption)
                        Text("\(tile.runningSubagents)")
                            .font(Theme.captionLarge)
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("서브에이전트 \(tile.runningSubagents)")
                }
            }
            if let file = SessionFormat.recentFileName(session: tile.session) {
                Text(file)
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, Theme.Spacing.s + 2)
        .padding(.vertical, Theme.Spacing.s + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Theme.Radius.box).fill(Theme.bg) }
    }

    @ViewBuilder private var elapsed: some View {
        if isLive {
            Text(TimeFormat.elapsed(from: tile.session.startedAt, to: now))
                .font(Theme.captionLargeMedium)
                .foregroundStyle(Theme.liveText)
        } else {
            Text("멈춤 \(TimeFormat.elapsed(from: tile.session.lastSeenAt, to: now))")
                .font(Theme.captionLarge)
                .foregroundStyle(Theme.textMuted)
        }
    }
}
