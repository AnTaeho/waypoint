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
        let activity = SessionActivityRules.activity(session, now: now, timeout: stallTimeout)
        if activity == .ended || activity == .expired { return .ended }
        return activity.isBusy ? .live : .stalled
    }

    /// 완료한 카드에서 떨어진 대화는 새 사용자 요청이 올 때까지 작업중 타일로 되살리지 않는다.
    /// 대화 종료·기록 삭제와는 별개인 표시 규칙이다. 아직 도는 하위 작업은 계속 보인다.
    public static func hasUnassignedWork(_ session: Session, now: Date,
                                         stallTimeout: TimeInterval = defaultStallTimeout) -> Bool {
        let links = session.cardSessions ?? []
        guard let latest = links.compactMap(\.detachedAt).max() else { return true }
        let lastLinks = links.filter { $0.detachedAt == latest }
        guard lastLinks.allSatisfy({ $0.card?.status == .done }),
              (session.lastPromptAt ?? .distantPast) <= latest
        else { return true }
        return (session.children ?? []).contains {
            state(of: $0, now: now, stallTimeout: stallTimeout) != .ended
        }
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

public enum SessionStateCache {
    /// 끝나지 않은 세션의 저장 캐시(`stateRaw`)를 지금 판정으로 맞춘다. 바뀐 세션 수를 돌려준다.
    /// 판정 자체는 늘 `SessionRules.state`로 다시 하므로, 캐시는 iPhone 동기화(M6)와 조회 편의용이다.
    /// 저장(save)은 호출 쪽에서 한다.
    @discardableResult
    public static func refresh(
        _ sessions: [Session],
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> Int {
        var changed = 0
        for session in sessions {
            let state = SessionRules.state(of: session, now: now, stallTimeout: stallTimeout)
            if session.cachedState != state {
                session.cachedState = state
                changed += 1
            }
        }
        return changed
    }
}
