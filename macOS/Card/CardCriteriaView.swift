import SwiftUI
import WaypointKit

/// 완료 조건 체크리스트: 「완료 조건 2 / 4」와 체크 상자. 체크하면 바로 저장한다.
struct CardCriteriaView: View {
    let card: Card
    /// (순번, 체크 여부)
    let setCriterion: (Int, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text("완료 조건")
                    .font(Theme.sectionLarge)
                    .foregroundStyle(Theme.text)
                Text("\(card.doneCriteriaCount) / \(card.criteria.count)")
                    .font(Theme.detailBody)
                    .foregroundStyle(Theme.textMuted)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s + 1) {
                ForEach(Array(card.criteria.enumerated()), id: \.offset) { index, criterion in
                    Toggle(isOn: binding(index)) {
                        Text(criterion.text)
                            .font(Theme.detailBody)
                            .foregroundStyle(criterion.isDone ? Theme.textMuted : Theme.text)
                            .strikethrough(criterion.isDone, color: Theme.textMuted)
                    }
                    .toggleStyle(.checkbox)
                    .tint(Theme.done)
                }
            }
        }
    }

    private func binding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { card.criteria.indices.contains(index) && card.criteria[index].isDone },
            set: { setCriterion(index, $0) }
        )
    }
}
