import Foundation
import SwiftData

/// `check` 이벤트 하나(검증 근거). payload 키는 SPEC 4장 「검증 근거」.
/// payload에 `text` 키를 두지 않는다: 옛 앱은 모르는 이벤트 종류를 `note`로 읽고, `text` 없는 메모는 숨긴다.
public struct CheckRecord: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let at: Date
    public let command: String
    public let outcome: CheckOutcome
    public let source: CheckSource
    /// 완료 조건 번호(0부터). 훅 기록은 늘 nil.
    public let criterion: Int?
    /// 보고 때의 완료 조건 글. 조건을 고쳐 글이 달라지면 그 조건의 근거로 쓰지 않는다.
    public let criterionText: String?
    public let detail: String?
    public let exitCode: Int?
    public let provider: AgentProvider?

    public init(id: UUID = UUID(), at: Date, command: String, outcome: CheckOutcome, source: CheckSource,
                criterion: Int? = nil, criterionText: String? = nil, detail: String? = nil,
                exitCode: Int? = nil, provider: AgentProvider? = nil) {
        self.id = id
        self.at = at
        self.command = command
        self.outcome = outcome
        self.source = source
        self.criterion = criterion
        self.criterionText = criterionText
        self.detail = detail
        self.exitCode = exitCode
        self.provider = provider
    }

    /// `check` 이벤트가 아니거나 필수 값이 없으면 nil.
    public init?(event: Event) {
        guard event.type == .check else { return nil }
        let p = event.payloadValues
        guard let command = p["command"]?.stringValue,
              let outcome = p["outcome"]?.stringValue.flatMap(CheckOutcome.init(rawValue:)),
              let source = p["source"]?.stringValue.flatMap(CheckSource.init(rawValue:))
        else { return nil }
        self.init(id: event.id, at: event.at, command: command, outcome: outcome, source: source,
                  criterion: p["criterion"]?.intValue, criterionText: p["criterionText"]?.stringValue,
                  detail: p["detail"]?.stringValue, exitCode: p["exitCode"]?.intValue,
                  provider: p["provider"]?.stringValue.flatMap(AgentProvider.init(rawValue:)))
    }

    var payload: [String: EventValue] {
        var p: [String: EventValue] = [
            "command": .string(command), "outcome": .string(outcome.rawValue), "source": .string(source.rawValue),
        ]
        if let criterion { p["criterion"] = .int(criterion) }
        if let criterionText { p["criterionText"] = .string(criterionText) }
        if let detail { p["detail"] = .string(detail) }
        if let exitCode { p["exitCode"] = .int(exitCode) }
        if let provider { p["provider"] = .string(provider.rawValue) }
        return p
    }

    /// 짝짓기용 검증 조각들(검증 명령이 아니면 빈 배열).
    public var keys: [String] { VerificationCommand.parse(command)?.keys ?? [] }
}

/// 완료 조건 하나의 근거 상태.
public struct CriterionEvidence: Sendable, Hashable {
    public enum State: String, Sendable, Hashable {
        case unverified, passed, failed, skipped
    }
    public let state: State
    /// 상태를 정한 근거의 출처. 미검증이면 nil.
    public let source: CheckSource?
    /// 근거 시각(확인됨이면 명령을 실행한 시각). 미검증이면 nil.
    public let at: Date?
    public let command: String?
    /// 근거 시각 뒤에 이 카드의 파일이 바뀌었다(「변경 후 미검증」).
    public let isStale: Bool

    public static let unverified = CriterionEvidence(state: .unverified, source: nil, at: nil, command: nil, isStale: false)
}

/// 카드의 검증 근거를 완료 조건별 상태로 모은다(SPEC 4장 「완료 조건 근거 상태」). 순수 함수.
/// - 조건 상태는 그 조건에 직접 붙은 에이전트 보고가 기준이다. 근거가 없으면 미검증.
/// - 훅 기록은 같은 검증 명령이고 보고 전 `confirmWindow` 안이면 보고를 「확인됨」으로 올린다. 결과가 다르면 훅 결과를 따른다.
///   보고 뒤에 같은 명령을 다시 돌린 훅 기록(결과가 확실한 것)이 있으면 그것이 최신 근거다.
/// - 근거 시각 뒤에 이 카드의 `file.changed`가 있으면 오래된 근거다. 커밋은 코드를 바꾸지 않아 보지 않는다.
/// - 세션 종료·연결 해제·체크박스는 상태에 영향을 주지 않는다.
public enum CardEvidence {

    /// 훅 기록이 보고를 확인하는 시간 창(보고 전 15분).
    public static let confirmWindow: TimeInterval = 15 * 60

    public static func records(for card: Card) -> [CheckRecord] {
        (card.events ?? []).compactMap(CheckRecord.init(event:)).sorted { $0.at > $1.at }
    }

    /// 이 카드의 파일 변경 시각들.
    public static func changeTimes(for card: Card) -> [Date] {
        (card.events ?? []).filter { $0.type == .fileChanged }.map(\.at)
    }

    public static func criteria(for card: Card) -> [CriterionEvidence] {
        evaluate(criteria: card.criteria, records: records(for: card), changes: changeTimes(for: card))
    }

    public static func evaluate(criteria: [Criterion], records: [CheckRecord], changes: [Date]) -> [CriterionEvidence] {
        let latestChange = changes.max()
        let hooks = records.filter { $0.source == .hook }
        return criteria.enumerated().map { index, criterion in
            let reports = records.filter {
                $0.source == .agent && $0.criterion == index && ($0.criterionText.map { $0 == criterion.text } ?? true)
            }
            guard let report = reports.max(by: { $0.at < $1.at }) else { return .unverified }
            let decided = decide(report: report, hooks: hooks)
            let stale = decided.state != .skipped && decided.at.map { at in latestChange.map { $0 > at } ?? false } ?? false
            return CriterionEvidence(state: decided.state, source: decided.source, at: decided.at,
                                     command: decided.command, isStale: stale)
        }
    }

    static func decide(report: CheckRecord, hooks: [CheckRecord]) -> CriterionEvidence {
        let reported = CriterionEvidence(state: state(report.outcome), source: .agent, at: report.at,
                                         command: report.command, isStale: false)
        guard report.outcome != .skipped else { return reported }
        let keys = report.keys
        guard !keys.isEmpty else { return reported }
        let matching = hooks.filter { hook in
            hook.outcome == .pass || hook.outcome == .fail
        }.filter { hook in
            let hookKeys = Set(hook.keys)
            return keys.allSatisfy(hookKeys.contains) && hook.at >= report.at.addingTimeInterval(-confirmWindow)
        }
        let latest = matching.max { $0.at < $1.at }
        guard let latest else { return reported }
        // 보고 뒤에 다시 돌렸거나, 보고 전 실행이 보고와 같거나 다르면 → 훅 결과
        return CriterionEvidence(state: state(latest.outcome), source: .hook, at: latest.at,
                                 command: latest.command, isStale: false)
    }

    static func state(_ outcome: CheckOutcome) -> CriterionEvidence.State {
        switch outcome {
        case .pass: .passed
        case .fail: .failed
        case .skipped: .skipped
        case .unknown: .unverified
        }
    }

    /// 근거 기록 한 건이 그 뒤 파일 변경으로 오래됐는지.
    public static func isStale(_ record: CheckRecord, changes: [Date]) -> Bool {
        changes.contains { $0 > record.at }
    }

    // MARK: - 기록

    /// 근거를 카드 이벤트로 남긴다. 저장은 호출 쪽에서.
    @discardableResult
    public static func record(_ record: CheckRecord, card: Card, session: Session?, toolUseID: String? = nil,
                              in context: ModelContext) -> Event {
        var payload = record.payload
        if let toolUseID { payload["toolUseId"] = .string(toolUseID) }
        return Event.record(.check, in: context, card: card, session: session, at: record.at, payload: payload)
    }

    /// 같은 도구 호출의 근거가 이미 있는지(재수신 중복 방지).
    public static func hasRecord(card: Card, toolUseID: String) -> Bool {
        (card.events ?? []).contains { $0.type == .check && $0.payloadValues["toolUseId"]?.stringValue == toolUseID }
    }
}
