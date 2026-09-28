import SwiftData
import SwiftUI
import WaypointKit

/// 방금 기록된 아이디어: 점선 카드마다 「다음 할 일로」「보관」.
struct PhoneIdeaSection: View {
    let cards: [Card]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Phone.cardGap) {
            Text("방금 기록된 아이디어")
                .font(Theme.Phone.section)
                .foregroundStyle(Theme.text)
            ForEach(cards) { card in
                PhoneIdeaCard(card: card, now: now)
            }
        }
    }
}

struct PhoneIdeaCard: View {
    let card: Card
    let now: Date
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            NavigationLink(value: card) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("\(card.displayID) · \(TimeFormat.relative(card.createdAt, now: now))")
                        .font(Theme.Phone.meta)
                        .foregroundStyle(Theme.textMuted)
                    Text(card.title)
                        .font(Theme.Phone.cardTitle)
                        .foregroundStyle(Theme.text)
                        .lineSpacing(Theme.Phone.titleLineSpacing)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: Theme.Spacing.s) {
                pill("다음 할 일로") { PhoneIdeaAction.move(card, to: .next, in: context) }
                pill("보관") { PhoneIdeaAction.move(card, to: .archived, in: context) }
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Phone.cardPadding)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Phone.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Phone.cardRadius)
                .strokeBorder(
                    Theme.ideaBorder,
                    style: StrokeStyle(lineWidth: Theme.Size.liveBorder, dash: Theme.Size.ideaCardDash)
                )
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Phone.button)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, Theme.Phone.buttonPaddingH)
                .frame(height: Theme.Phone.buttonHeight)
                .background(Theme.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
        }
        .buttonStyle(.plain)
    }

}

/// 아이디어 분류: 상태를 옮기고 바로 저장한다(저장하면 CloudKit으로 Mac에 간다).
enum PhoneIdeaAction {
    @MainActor
    static func move(_ card: Card, to status: CardStatus, in context: ModelContext) {
        withAnimation {
            do {
                try CardLifecycle.move(card, to: status, at: Date(), in: context)
                try context.save()
            } catch {
                // active로 옮기는 경우만 던지고, 여기서는 오지 않는다. 저장 실패는 다음 저장 때 다시 시도된다.
                print("Waypoint: 카드 옮기기 실패 \(error)")
            }
        }
    }
}
