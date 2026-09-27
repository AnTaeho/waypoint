import SwiftUI
import WaypointKit

/// 작업중 표 한 줄. live는 흰 바탕·펄스 점·경과, stalled는 속 빈 점·「멈춤 N분」.
struct ActiveWorkRowView: View {
    let row: DashboardRow
    let now: Date
    let columns: ActiveColumns

    private var isLive: Bool { row.workState == .live }

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.s) {
                WorkStateDot(state: row.workState)
                Text(row.card.displayID)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text)
            }
            .padding(.leading, row.depth > 0 ? Theme.Spacing.indent : 0)
            .frame(width: Theme.Columns.activeCard, alignment: .leading)

            Text(row.card.title)
                .font(Theme.bodyMedium)
                .foregroundStyle(isLive ? Theme.text : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let file = columns.file {
                Text(SessionFormat.recentFileName(card: row.card, session: row.session) ?? "")
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

    @ViewBuilder private var elapsed: some View {
        if isLive {
            Text(TimeFormat.elapsed(from: row.session.startedAt, to: now))
                .font(Theme.captionLargeMedium)
                .foregroundStyle(Theme.liveText)
        } else {
            Text("멈춤 \(TimeFormat.elapsed(from: row.session.lastSeenAt, to: now))")
                .font(Theme.captionLarge)
                .foregroundStyle(Theme.textMuted)
        }
    }
}
