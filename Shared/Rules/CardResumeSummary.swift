import Foundation

/// 재개 전에 한곳에서 보는 요약: 목표, 남은 완료 조건, 미검증 조건, 마지막 메모와 작성 시점.
/// 복사 문맥(`CardResumeContext.text`)과 같은 기록을 읽고 아무것도 바꾸지 않는다.
public struct CardResumeSummary {
    public struct Item: Equatable {
        /// 완료 조건 번호(1부터)
        public let number: Int
        public let text: String
        /// 미검증 항목일 때 근거 상태(「미검증」「실패 · 보고」「변경 후 미검증 · 확인됨」)
        public let evidence: String?
        /// 근거가 실패(변경 후 미검증이 아닌)
        public var isFailure = false
    }

    public let title: String
    /// 본문의 첫 글줄(Markdown 머리 기호를 뗀 것). 본문이 없으면 nil.
    public let goalLine: String?
    public let remaining: [Item]
    public let unverified: [Item]
    public let note: String?
    public let freshness: HandoffFreshness?

    public init(card: Card) {
        title = card.title
        goalLine = Self.firstLine(card.body)
        remaining = card.criteria.enumerated().filter { !$0.element.isDone }
            .map { Item(number: $0.offset + 1, text: $0.element.text, evidence: nil) }
        let evidence = CardEvidence.criteria(for: card)
        unverified = card.criteria.enumerated().compactMap { index, criterion in
            guard index < evidence.count, Self.needsVerification(evidence[index]) else { return nil }
            return Item(number: index + 1, text: criterion.text,
                        evidence: EvidenceFormat.criterionLabel(evidence[index]),
                        isFailure: evidence[index].state == .failed && !evidence[index].isStale)
        }
        let trimmed = card.nextSessionNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        note = trimmed.isEmpty ? nil : trimmed
        freshness = HandoffFreshness.evaluate(card)
    }

    /// 미검증·실패·변경 후 미검증. 건너뜀은 넣지 않는다(에이전트가 이유를 남긴 판단이다).
    public static func needsVerification(_ evidence: CriterionEvidence) -> Bool {
        evidence.isStale || evidence.state == .unverified || evidence.state == .failed
    }

    static func firstLine(_ body: String) -> String? {
        for raw in body.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            // 머리(#)·인용(>)·목록(- , * ) 기호만 뗀다. 굵게(**)는 남긴다.
            while let range = line.range(of: #"^(#+|>|[-*] )\s*"#, options: .regularExpression) {
                line.removeSubrange(range)
            }
            if !line.isEmpty { return line }
        }
        return nil
    }
}
