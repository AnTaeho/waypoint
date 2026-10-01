import SwiftUI
import WaypointKit

/// 카드가 없는 세션은 누를 수 없고, 연결된 카드는 기존 카드 상세로 이동한다.
struct DashboardWorkTile: View {
    let row: DashboardRow
    let now: Date

    var body: some View {
        if let card = row.card {
            NavigationLink(value: card) { tile }.buttonStyle(.plain)
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ViewThatFits(in: .horizontal) {
                HStack { project; Spacer(minLength: Theme.Spacing.m); elapsed }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { project; elapsed }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(row.card?.title ?? SessionFormat.noCardTitle(prompt: row.session.lastPrompt).text)
                    .font(row.card == nil ? Theme.sessionTileTitle : Theme.cardTitle)
                    .foregroundStyle(Theme.text).lineLimit(2)
                if let card = row.card {
                    Text(card.displayID).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) { session; Spacer(minLength: Theme.Spacing.s); file }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { session; file }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .strokeBorder(row.workState == .live && row.card != nil ? Theme.live : Theme.border,
                              lineWidth: Theme.Size.cardBorder)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }

    private var project: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(row.session.project?.key ?? "").font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
            Text(row.session.project?.name ?? "").font(Theme.caption).lineLimit(1)
        }
    }

    private var elapsed: some View {
        HStack(spacing: Theme.Spacing.s) {
            WorkStateDot(state: row.workState)
            Text(SessionFormat.rowElapsed(
                state: row.workState, lastPromptAt: row.session.lastPromptAt, attachedAt: row.attachedAt,
                lastSeenAt: row.session.lastSeenAt, now: now, session: row.session
            ) ?? "작업 중")
            .font(Theme.captionLargeMedium)
            .foregroundStyle(row.workState == .live ? Theme.liveText : Theme.textMuted)
            .fixedSize()
        }
    }

    private var session: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text(row.session.provider.name).font(Theme.captionLargeMedium)
            Text(SessionFormat.label(kind: row.session.kind, id: row.session.sourceID,
                                     agentName: row.session.agentName))
                .font(Theme.monoSmall).foregroundStyle(Theme.textMuted).lineLimit(1)
        }
    }

    @ViewBuilder private var file: some View {
        let name = row.card.map { SessionFormat.recentFileName(card: $0, session: row.session) }
            ?? SessionFormat.recentFileName(session: row.session)
        if let name {
            Text(name).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                .lineLimit(1).truncationMode(.middle).help(name)
        }
    }
}
