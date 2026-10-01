import Foundation

/// 재개 진행 단계: 준비됨(복사 전) → 복사함(새 세션 연결 전) → 연결됨(새 세션이 카드에 붙음).
/// 연결됨은 `CardResumeAttempt`가 실제 카드 연결을 확인할 때만이다. 복사·터미널 열기만으로는 복사함에 머문다.
public enum CardResumeStatus: Equatable {
    case ready
    case copied(AgentProvider)
    case connected(AgentProvider)
    case disconnected(AgentProvider)
    case unavailable(String)

    public static func of(_ card: Card, attempt: CardResumeAttempt?) -> Self {
        guard let attempt else {
            return CardResumeContext.unavailableReason(card).map(Self.unavailable) ?? .ready
        }
        switch attempt.state(for: card) {
        case .waiting: return .copied(attempt.provider)
        case .connected: return .connected(attempt.provider)
        case .disconnected: return .disconnected(attempt.provider)
        case .unavailable(let reason): return .unavailable(reason)
        }
    }

    public var label: String {
        switch self {
        case .ready: "준비됨"
        case .copied(let provider): "복사함 · \(provider.name) 새 세션 연결 전"
        case .connected(let provider): "연결됨 · \(provider.name) 새 세션"
        case .disconnected(let provider): "연결 끊김 · \(provider.name)"
        case .unavailable(let reason): "재개 불가 · \(reason)"
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
