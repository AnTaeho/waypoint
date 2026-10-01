import Foundation

/// 검증 근거 화면 문구. 짧은 사실만 쓴다(DESIGN 「화면 문구」).
public enum EvidenceFormat {

    public static func outcomeName(_ outcome: CheckOutcome) -> String {
        switch outcome {
        case .pass: "통과"
        case .fail: "실패"
        case .skipped: "건너뜀"
        case .unknown: "결과 모름"
        }
    }

    /// 출처: 명령 실행을 직접 본 것은 「확인됨」, 에이전트가 알린 것은 「보고」.
    public static func sourceName(_ source: CheckSource) -> String {
        switch source {
        case .hook: "확인됨"
        case .agent: "보고"
        }
    }

    /// 완료 조건 줄의 상태 이름. 근거 뒤에 파일이 바뀌었으면 결과 대신 「변경 후 미검증」.
    public static func stateName(_ evidence: CriterionEvidence) -> String {
        if evidence.isStale { return "변경 후 미검증" }
        switch evidence.state {
        case .passed: return "통과"
        case .failed: return "실패"
        case .skipped: return "건너뜀"
        case .unverified: return "미검증"
        }
    }

    /// 완료 조건 줄의 짧은 표시: 「통과 · 확인됨」「미검증」.
    public static func criterionLabel(_ evidence: CriterionEvidence) -> String {
        guard let source = evidence.source else { return stateName(evidence) }
        return "\(stateName(evidence)) · \(sourceName(source))"
    }

    /// 마우스를 올리면 보이는 글: 명령과 시각, 오래된 근거면 원래 결과.
    public static func criterionHelp(_ evidence: CriterionEvidence, now: Date) -> String? {
        guard let command = evidence.command, let at = evidence.at else { return nil }
        var parts = [command, TimeFormat.timestamp(at, now: now)]
        if evidence.isStale {
            let previous = CriterionEvidence(state: evidence.state, source: evidence.source, at: at,
                                             command: command, isStale: false)
            parts.append("이전 결과 \(stateName(previous))")
        }
        return parts.joined(separator: "\n")
    }

    /// 히스토리 줄의 명령(모노). 길면 줄인다.
    public static func shortCommand(_ command: String, limit: Int = 60) -> String {
        let line = command.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// 히스토리·활동 탭 문구: 「검증 통과 · 확인됨」「조건 2 검증 실패 · 보고」.
    public static func historyText(_ record: CheckRecord) -> String {
        let subject = record.criterion.map { "조건 \($0 + 1) 검증" } ?? "검증"
        return "\(subject) \(outcomeName(record.outcome)) · \(sourceName(record.source))"
    }
}
