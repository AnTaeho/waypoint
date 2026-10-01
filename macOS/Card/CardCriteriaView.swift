import SwiftUI
import WaypointKit

/// 완료 조건 체크리스트: 「완료 조건 2 / 4」와 체크 상자, 줄마다 근거 상태(통과·실패·미검증·변경 후 미검증과 출처).
/// 체크는 사용자 판단 표시라 근거 상태와 따로 둔다. 체크하면 바로 저장한다.
struct CardCriteriaView: View {
    let card: Card
    let evidence: [CriterionEvidence]
    let now: Date
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
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                        Toggle(isOn: binding(index)) {
                            Text(criterion.text)
                                .font(Theme.detailBody)
                                .foregroundStyle(criterion.isDone ? Theme.textMuted : Theme.text)
                                .strikethrough(criterion.isDone, color: Theme.textMuted)
                        }
                        .toggleStyle(.checkbox)
                        .tint(Theme.done)
                        Spacer(minLength: Theme.Spacing.s)
                        CriterionEvidenceLabel(evidence: evidence.indices.contains(index) ? evidence[index] : .unverified,
                                               now: now)
                    }
                    .frame(maxWidth: Theme.Size.detailBodyMaxWidth, alignment: .leading)
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

/// 완료 조건 줄 오른쪽 근거 상태: 「통과 · 확인됨」. 마우스를 올리면 명령과 시각.
struct CriterionEvidenceLabel: View {
    let evidence: CriterionEvidence
    let now: Date

    var body: some View {
        Text(EvidenceFormat.criterionLabel(evidence))
            .font(evidence.state == .unverified || evidence.isStale ? Theme.captionLarge : Theme.captionLargeMedium)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .help(EvidenceFormat.criterionHelp(evidence, now: now) ?? "")
    }

    private var color: Color {
        if evidence.isStale { return Theme.Evidence.muted }
        switch evidence.state {
        case .passed: return Theme.Evidence.pass
        case .failed: return Theme.Evidence.fail
        case .unverified, .skipped: return Theme.Evidence.muted
        }
    }
}
