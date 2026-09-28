import SwiftUI
import WaypointKit

/// 보드 카드 한 장. 칸에 따라 모양이 다르다(DESIGN.md 「상태 표현 규칙」).
/// - 아이디어: 점선 테두리, `bgPanel`
/// - 다음: 흰 카드
/// - 작업중: `live` 1.5pt 테두리 + 그림자, 점, 세션 정보 상자, 완료 조건 막대
/// - 완료: 흰 카드, 불투명도 0.85, 날짜·세션 횟수
struct BoardCardView: View {
    let card: Card
    let column: BoardColumn
    let now: Date

    var body: some View {
        let link = column == .active ? BoardQuery.primaryLink(of: card, now: now) : nil
        let state = column == .active ? CardRules.workState(of: card, now: now) : .none
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                WorkStateDot(state: state)
                Text(card.displayID)
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                Spacer(minLength: 0)
                if let link, let session = link.session,
                   let time = CardFormat.workTime(
                       state: state, attachedAt: link.attachedAt, lastSeenAt: session.lastSeenAt, now: now
                   ) {
                    Text(time)
                        .font(state == .live ? Theme.captionLargeMedium : Theme.captionLarge)
                        .foregroundStyle(state == .live ? Theme.liveText : Theme.textMuted)
                        .lineLimit(1)
                }
            }
            Text(card.title)
                .font(Theme.cardTitle)
                .foregroundStyle(column == .done ? Theme.textSecondary : Theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            footer(link: link)
        }
        .padding(Theme.Spacing.rowH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardBackground }
        .opacity(column == .done ? Theme.Board.doneOpacity : 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder private func footer(link: CardSession?) -> some View {
        switch column {
        case .idea, .next:
            Text(CardFormat.originLine(card, now: now))
                .font(Theme.captionLarge)
                .foregroundStyle(Theme.textMuted)
        case .active:
            if let link, let session = link.session {
                BoardSessionBox(card: card, session: session)
            }
            if !card.criteria.isEmpty {
                CriteriaProgress(done: card.doneCriteriaCount, total: card.criteria.count)
            }
        case .done:
            let line = CardFormat.doneLine(doneAt: card.doneAt, stats: BoardQuery.stats(of: card), now: now)
            if !line.isEmpty {
                Text(line)
                    .font(Theme.captionLarge)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card)
        switch column {
        case .idea:
            shape.fill(Theme.bgPanel)
                .overlay {
                    shape.strokeBorder(
                        Theme.ideaBorder,
                        style: StrokeStyle(lineWidth: Theme.Size.liveBorder, dash: Theme.Size.ideaCardDash)
                    )
                }
        case .next, .done:
            shape.fill(Theme.surface)
                .overlay { shape.strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
        case .active:
            shape.fill(Theme.surface)
                .overlay { shape.strokeBorder(Theme.live, lineWidth: Theme.Size.liveBorder) }
                .shadow(color: Theme.liveShadow, radius: Theme.Size.liveShadowRadius, y: Theme.Size.liveShadowY)
        }
    }
}

/// 완료 조건 진행: 「완료 조건 2 / 4」와 막대.
private struct CriteriaProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("완료 조건")
                Spacer(minLength: 0)
                Text("\(done) / \(total)").monospacedDigit()
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.textSecondary)
            GeometryReader { proxy in
                Capsule().fill(Theme.divider)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.live)
                            .frame(width: proxy.size.width * CGFloat(done) / CGFloat(max(total, 1)))
                    }
            }
            .frame(height: Theme.Size.progressHeight)
        }
    }
}
