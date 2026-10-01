import SwiftUI
import WaypointKit

/// 작업중 표 한 줄. live는 흰 바탕·펄스 점·경과, stalled는 속 빈 점·「멈춤 N분」.
/// 카드 없는 세션 줄은 카드 칸을 비우고 제목 자리에 그 세션의 마지막 요청 문장(없으면 「카드 없음」)을 흐리게 둔다.
struct ActiveWorkRowView: View {
    let row: DashboardRow
    let now: Date
    let columns: ActiveColumns

    private var isLive: Bool { row.workState == .live }

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.s) {
                WorkStateDot(state: row.workState)
                Text(row.card?.displayID ?? "")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text)
            }
            .padding(.leading, row.depth > 0 ? Theme.Spacing.indent : 0)
            .frame(width: Theme.Columns.activeCard, alignment: .leading)

            titleText
                .font(row.card == nil ? Theme.body : Theme.bodyMedium)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(row.card == nil ? row.session.lastPrompt ?? "" : "")

            if let file = columns.file {
                Text(recentFile ?? "")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: file, alignment: .leading)
            }

            if let session = columns.session {
                Text(SessionFormat.label(for: row.session))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: session, alignment: .leading)
            }

            elapsed
                .lineLimit(1)
                .frame(width: Theme.Columns.activeElapsed, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.rowH)
        .frame(height: Theme.Size.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row)
                .fill(isLive ? Theme.surface : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var titleText: Text {
        if let card = row.card { return Text(card.title) }
        return Text(SessionFormat.noCardTitle(prompt: row.session.lastPrompt).text)
    }

    private var titleColor: Color {
        if row.card == nil { return Theme.textMuted }
        return isLive ? Theme.text : Theme.textSecondary
    }

    private var recentFile: String? {
        guard let card = row.card else { return SessionFormat.recentFileName(session: row.session) }
        return SessionFormat.recentFileName(card: card, session: row.session)
    }

    /// 카드 줄은 연결 시각부터, 카드 없는 줄은 마지막 요청 시각부터(없으면 빈 글 — 열 폭은 그대로 둔다).
    private var elapsed: some View {
        Text(SessionFormat.rowElapsed(
            state: row.workState, lastPromptAt: row.session.lastPromptAt, attachedAt: row.attachedAt,
            lastSeenAt: row.session.lastSeenAt, now: now, session: row.session
        ) ?? "")
        .font(isLive ? Theme.captionLargeMedium : Theme.captionLarge)
        .foregroundStyle(isLive ? Theme.liveText : Theme.textMuted)
    }
}
