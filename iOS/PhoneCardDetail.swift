import SwiftUI
import WaypointKit

/// 카드 상세(읽기 전용): ID·프로젝트·상태, 제목, 본문, 완료 조건.
struct PhoneCardDetail: View {
    let card: Card

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Phone.sectionGap) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(meta)
                        .font(Theme.Phone.meta)
                        .foregroundStyle(Theme.textMuted)
                    Text(card.title)
                        .font(Theme.Phone.detailTitle)
                        .foregroundStyle(Theme.text)
                        .lineSpacing(Theme.Phone.titleLineSpacing)
                }
                if !card.body.isEmpty {
                    Text(card.body)
                        .font(Theme.Phone.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(Theme.Phone.titleLineSpacing)
                        .textSelection(.enabled)
                }
                if !card.criteria.isEmpty {
                    criteria
                }
            }
            .padding(.horizontal, Theme.Phone.gutter)
            .padding(.vertical, Theme.Phone.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 「LDG-14 · 가계부 앱 · 다음 할 일」
    private var meta: String {
        [card.displayID, card.project?.name, CardFormat.statusName(card.status)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var criteria: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("완료 조건 \(card.doneCriteriaCount)/\(card.criteria.count)")
                .font(Theme.Phone.section)
                .foregroundStyle(Theme.text)
            ForEach(Array(card.criteria.enumerated()), id: \.offset) { _, criterion in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Image(systemName: criterion.isDone ? "checkmark.square" : "square")
                        .foregroundStyle(criterion.isDone ? Theme.done : Theme.textMuted)
                    Text(criterion.text)
                        .font(Theme.Phone.body)
                        .foregroundStyle(criterion.isDone ? Theme.textMuted : Theme.text)
                        .strikethrough(criterion.isDone, color: Theme.textMuted)
                }
            }
        }
    }
}
