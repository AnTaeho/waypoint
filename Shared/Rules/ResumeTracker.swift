import Foundation

/// 재개 시간 지표(TRK-11): 카드의 재개 문맥을 처음 복사한 시각부터 그 카드에 새 세션이 연결된 시각까지.
/// 연결 판정은 `CardResumeAttempt`(TRK-31)를 그대로 쓴다. 대기 목록은 메모리에만 둔다(앱을 끄면 사라진다).
public struct ResumeTracker {
    /// 이 시간 안에 연결되지 않으면 버린다(재개하지 않은 것으로 본다).
    public static let lifetime: TimeInterval = 24 * 60 * 60

    struct Pending {
        var attempt: CardResumeAttempt
        /// 연결 전까지 이 카드를 처음 복사한 시각. 도구를 바꿔 다시 복사해도 앞당겨지지 않는다.
        var since: Date
    }

    private var pending: [UUID: Pending] = [:]

    public init() {}

    public var isEmpty: Bool { pending.isEmpty }
    public var cardIDs: [UUID] { Array(pending.keys) }

    /// 복사 성공. 같은 카드를 다시 복사하면 판정은 새 복사(도구·이전 세션)로, 시작 시각은 처음 것으로.
    public mutating func copied(_ attempt: CardResumeAttempt) {
        let since = pending[attempt.cardID].map { min($0.since, attempt.copiedAt) } ?? attempt.copiedAt
        pending[attempt.cardID] = Pending(attempt: attempt, since: since)
    }

    /// 연결된 카드의 걸린 시간(초)을 돌려주고 목록에서 뺀다. 사라진 카드·재개할 수 없게 된 카드·기한 지난 것은 조용히 뺀다.
    public mutating func check(_ cards: [Card], now: Date) -> [TimeInterval] {
        var durations: [TimeInterval] = []
        for (id, item) in pending {
            guard now.timeIntervalSince(item.since) <= Self.lifetime,
                  let card = cards.first(where: { $0.id == id }) else {
                pending[id] = nil
                continue
            }
            if let at = item.attempt.connectedAt(for: card) {
                durations.append(at.timeIntervalSince(item.since))
                pending[id] = nil
            } else if case .unavailable = item.attempt.state(for: card) {
                pending[id] = nil
            }
        }
        return durations
    }
}
