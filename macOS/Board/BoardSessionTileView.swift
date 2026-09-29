import SwiftUI
import WaypointKit

/// 작업중 칸의 카드 없는 세션 타일. 제목 자리에 그 세션의 마지막 요청 문장(없으면 「카드 없음」),
/// 그 아래 점·세션·경과, 최근 파일·서브에이전트 수. 흰 바탕 `border` 1pt로 카드보다 한 단 낮게 보인다.
/// 끌거나 누를 수 없다.
struct BoardSessionTileView: View {
    let tile: BoardSessionTile
    let now: Date

    private var isLive: Bool { tile.workState == .live }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            title
            // 좁은 칸에서 경과가 잘리지 않게, 한 줄에 안 들어가면 세션을 아래 줄로 내린다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    WorkStateDot(state: tile.workState)
                    sessionLabel
                    Spacer(minLength: Theme.Spacing.s)
                    elapsed
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.s) {
                        WorkStateDot(state: tile.workState)
                        elapsed
                    }
                    sessionLabel
                }
            }
            if hasDetail { detailBox }
        }
        .padding(.horizontal, Theme.Board.cardPaddingH)
        .padding(.vertical, Theme.Board.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.card)
            shape.fill(Theme.surface)
                .overlay { shape.strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
        }
    }

    @ViewBuilder private var title: some View {
        let title = SessionFormat.noCardTitle(prompt: tile.session.lastPrompt)
        let text = Text(title.text)
            .font(Theme.sessionTileTitle)
            .foregroundStyle(title.isPrompt ? Theme.text : Theme.textMuted)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if title.isPrompt, let full = tile.session.lastPrompt {
            text.help(full)
        } else {
            text
        }
    }

    private var sessionLabel: some View {
        Text(SessionFormat.label(for: tile.session))
            .font(Theme.monoCaption)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var recentFile: String? { SessionFormat.recentFileName(session: tile.session) }
    private var hasDetail: Bool { recentFile != nil || tile.runningSubagents > 0 }

    private var detailBox: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            if let file = recentFile {
                Text(file)
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
        .padding(.horizontal, Theme.Spacing.s + 2)
        .padding(.vertical, Theme.Spacing.s + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Theme.Radius.box).fill(Theme.bg) }
    }

    /// 마지막 요청 시각부터(없으면 비움). 멈춤이면 「멈춤 N분」.
    @ViewBuilder private var elapsed: some View {
        if let text = SessionFormat.rowElapsed(
            state: tile.workState, lastPromptAt: tile.session.lastPromptAt, attachedAt: nil,
            lastSeenAt: tile.session.lastSeenAt, now: now
        ) {
            Text(text)
                .font(isLive ? Theme.captionLargeMedium : Theme.captionLarge)
                .foregroundStyle(isLive ? Theme.liveText : Theme.textMuted)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
