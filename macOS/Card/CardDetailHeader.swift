import SwiftUI
import WaypointKit

/// 카드 상세 머리: 경로(프로젝트 / 카드 ID), 상태·종류 배지, 「완료로 옮기기」, 제목.
struct CardDetailHeader: View {
    let card: Card
    let now: Date
    let moveToDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text(card.project?.name ?? "")
                    .font(Theme.captionLarge)
                    .foregroundStyle(Theme.textMuted)
                Text("/")
                    .font(Theme.captionLarge)
                    .foregroundStyle(Theme.textMuted)
                Text(card.displayID)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: Theme.Spacing.s) {
                CardStatusBadge(card: card, now: now)
                Text(CardFormat.kindName(card.kind))
                    .font(Theme.captionLarge)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.xxs + 1)
                    .overlay { Capsule().strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
                Spacer(minLength: 0)
                if card.status != .done && card.status != .archived {
                    Button("완료로 옮기기", systemImage: "checkmark", action: moveToDone)
                        .buttonStyle(.bordered)
                }
            }
            Text(card.title)
                .font(Theme.detailTitle)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// 상태 배지: 점 + 이름. 작업중이면 경과(「작업중 · 38분째」「작업중 · 멈춤 22분」).
struct CardStatusBadge: View {
    let card: Card
    let now: Date

    var body: some View {
        let work = CardRules.workState(of: card, now: now)
        HStack(spacing: Theme.Spacing.xs + 2) {
            dot(work)
            Text(label(work))
                .font(Theme.captionLargeMedium)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
        .background { Capsule().fill(background) }
    }

    private func label(_ work: CardWorkState) -> String {
        let name = CardFormat.statusName(card.status)
        if card.status == .active, let waiting = SessionWaiting.shown(for: card, now: now) {
            return "\(name) · \(waiting.text(now: now))"
        }
        guard card.status == .active,
              let link = BoardQuery.primaryLink(of: card, now: now),
              let session = link.session,
              let time = CardFormat.workTime(
                  state: work, attachedAt: link.attachedAt, lastSeenAt: session.lastSeenAt, now: now, session: session
              )
        else { return name }
        return "\(name) · \(time)"
    }

    @ViewBuilder private func dot(_ work: CardWorkState) -> some View {
        switch card.status {
        case .active:
            if work == .none { FilledDot(color: Theme.live) } else { WorkStateDot(state: work) }
        case .next: FilledDot(color: Theme.next)
        case .done: FilledDot(color: Theme.done)
        case .idea: IdeaDot()
        case .archived: FilledDot(color: Theme.ideaBorder)
        }
    }

    private var foreground: Color {
        switch card.status {
        case .active: Theme.liveText
        case .done: Theme.done
        case .next: Theme.next
        case .idea, .archived: Theme.textSecondary
        }
    }

    private var background: Color {
        switch card.status {
        case .active: Theme.liveBg
        case .done: Theme.doneBg
        case .next, .idea, .archived: Theme.bgSunken
        }
    }
}
