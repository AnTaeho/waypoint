import Foundation

public enum SessionRules {
    /// 멈춤 판정 기본값 15분.
    public static let defaultStallTimeout: TimeInterval = 15 * 60

    /// endedAt이 있으면 ended, 마지막 활동 후 stallTimeout을 **넘기면** stalled(정확히 같으면 live), 아니면 live.
    public static func state(
        endedAt: Date?,
        lastSeenAt: Date,
        now: Date,
        stallTimeout: TimeInterval = defaultStallTimeout
    ) -> SessionState {
        if endedAt != nil { return .ended }
        if now.timeIntervalSince(lastSeenAt) > stallTimeout { return .stalled }
        return .live
    }

    public static func state(
        of session: Session,
        now: Date,
        stallTimeout: TimeInterval = defaultStallTimeout
    ) -> SessionState {
        state(endedAt: session.endedAt, lastSeenAt: session.lastSeenAt, now: now, stallTimeout: stallTimeout)
    }
}

/// 카드에 붙은 세션 기준의 작업 상태(파생값).
public enum CardWorkState: String, Sendable, Hashable {
    case none, live, stalled
}

public enum CardRules {
    /// 열린 연결 중 live 세션이 하나라도 있으면 live, 열린 연결이 있는데 live가 없고 stalled가 있으면 stalled, 그 외 none.
    public static func workState(
        of card: Card,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> CardWorkState {
        var sawStalled = false
        for link in card.openCardSessions {
            guard let session = link.session else { continue }
            switch SessionRules.state(of: session, now: now, stallTimeout: stallTimeout) {
            case .live: return .live
            case .stalled: sawStalled = true
            case .ended: continue
            }
        }
        return sawStalled ? .stalled : .none
    }
}
