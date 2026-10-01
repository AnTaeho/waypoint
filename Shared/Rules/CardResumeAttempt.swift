import Foundation

/// 성공한 복사 시점의 화면 내 스냅샷. 연결의 인과관계나 실제 작업 시작을 추정하지 않는다.
public struct CardResumeAttempt {
    public let provider: AgentProvider
    public let copiedAt: Date
    public let cardID: UUID
    private let projectID: UUID?
    private let previousSessionIDs: Set<String>

    public enum State: Equatable {
        case waiting, connected, disconnected
        case unavailable(String)
    }

    public init(card: Card, provider: AgentProvider, at: Date) {
        self.provider = provider
        copiedAt = at
        cardID = card.id
        projectID = card.project?.id
        previousSessionIDs = Set((card.cardSessions ?? []).compactMap { $0.session?.id })
    }

    public func state(for card: Card) -> State {
        guard card.id == cardID, card.project?.id == projectID else { return .unavailable("작업 대상 변경됨") }
        if let reason = CardResumeContext.unavailableReason(card) { return .unavailable(reason) }
        let links = newLinks(card)
        if card.status == .active && links.contains(where: { $0.isOpen && $0.session?.endedAt == nil }) {
            return .connected
        }
        return links.isEmpty ? .waiting : .disconnected
    }

    /// 연결 확인(`connected`)일 때 그 연결이 붙은 가장 이른 시각. 재개 시간 지표가 쓴다(알아챈 시각은 쓰지 않는다).
    public func connectedAt(for card: Card) -> Date? {
        guard state(for: card) == .connected else { return nil }
        return newLinks(card).filter { $0.isOpen && $0.session?.endedAt == nil }.map(\.attachedAt).min()
    }

    /// 복사 뒤 같은 도구의 새 메인 세션이 이 카드에 붙은 연결
    private func newLinks(_ card: Card) -> [CardSession] {
        (card.cardSessions ?? []).filter { link in
            guard link.card?.id == cardID, link.attachedAt > copiedAt,
                  let session = link.session, session.provider == provider, session.kind == .main,
                  session.project?.id == projectID, !previousSessionIDs.contains(session.id) else { return false }
            return true
        }
    }

    public func label(for card: Card) -> String {
        switch state(for: card) {
        case .waiting: "\(provider.name) 문맥 복사됨 · 새 세션 연결 대기"
        case .connected: "복사 후 \(provider.name) 새 세션 연결 확인"
        case .disconnected: "복사 후 \(provider.name) 연결 해제됨"
        case .unavailable(let reason): "재개 확인 중단 · \(reason)"
        }
    }
}
