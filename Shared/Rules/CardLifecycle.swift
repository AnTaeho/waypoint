import Foundation
import SwiftData

public enum CardLifecycleError: Error, Equatable {
    /// active는 세션 연결로만 들어간다.
    case cannotMoveToActive
}

/// 카드·세션 연결과 상태 전이. 저장(save)은 호출 쪽에서 한다.
/// 모든 함수는 액터 격리가 없고, 넘겨받은 context가 속한 액터에서 불러야 한다.
public enum CardLifecycle {

    /// 세션을 카드에 연결한다. 카드가 active가 아니면 이전 상태를 기억하고 active로 바꾼다.
    /// 같은 카드·세션의 열린 연결이 이미 있으면 그것을 돌려주고 아무것도 기록하지 않는다.
    @discardableResult
    public static func attach(_ card: Card, _ session: Session, at date: Date, in context: ModelContext) -> CardSession {
        if let existing = card.openCardSessions.first(where: { $0.session === session }) {
            return existing
        }
        let link = CardSession(attachedAt: date)
        context.insert(link)
        link.card = card
        link.session = session

        Event.record(.cardAttached, in: context, card: card, session: session, at: date,
                     payload: ["sessionId": .string(session.id)])

        if card.status != .active {
            let from = card.status
            card.statusBeforeActive = from.rawValue
            card.status = .active
            Event.record(.cardStatus, in: context, card: card, session: session, at: date,
                         payload: ["from": .string(from.rawValue), "to": .string(CardStatus.active.rawValue)])
        }
        card.updatedAt = date
        return link
    }

    /// 카드·세션의 열린 연결을 닫는다. 남은 열린 연결이 없고 카드가 여전히 active면
    /// `statusBeforeActive`(없으면 next)로 돌린다. 사용자가 그사이 옮겼으면 그대로 둔다.
    /// 여기서 done으로 바꾸는 일은 없다(기억된 상태가 done이었던 경우만 done으로 돌아간다).
    public static func detach(_ card: Card, _ session: Session, at date: Date, in context: ModelContext) {
        let links = card.openCardSessions.filter { $0.session === session }
        guard !links.isEmpty else { return }
        for link in links { link.detachedAt = date }
        Event.record(.cardDetached, in: context, card: card, session: session, at: date,
                     payload: ["sessionId": .string(session.id)])

        guard card.openCardSessions.isEmpty, card.status == .active else { return }
        let restored = card.statusBeforeActive.flatMap(CardStatus.init(rawValue:)) ?? .next
        let target: CardStatus = restored == .active ? .next : restored
        card.status = target
        card.statusBeforeActive = nil
        card.updatedAt = date
        Event.record(.cardStatus, in: context, card: card, session: session, at: date,
                     payload: ["from": .string(CardStatus.active.rawValue), "to": .string(target.rawValue)])
    }

    /// 세션의 열린 연결을 모두 닫고 세션을 끝낸다. 이벤트 `session.end`는 기록하지 않는다(훅 처리 쪽 몫).
    public static func detachAll(_ session: Session, at date: Date, in context: ModelContext) {
        let cards = session.openCardSessions.compactMap(\.card)
        var seen = Set<ObjectIdentifier>()
        for card in cards where seen.insert(ObjectIdentifier(card)).inserted {
            detach(card, session, at: date, in: context)
        }
        session.endedAt = date
        session.cachedState = .ended
    }

    /// 사용자가 앱에서 카드를 옮긴다. active로는 못 옮긴다.
    /// done 진입 시 doneAt 설정, done에서 나오면 doneAt nil. active에서 나오면 statusBeforeActive를 지운다.
    /// 열린 세션 연결은 건드리지 않는다. 같은 상태로 옮기면 아무 일도 없다.
    public static func move(_ card: Card, to target: CardStatus, at date: Date, in context: ModelContext) throws {
        if target == .active { throw CardLifecycleError.cannotMoveToActive }
        let from = card.status
        guard from != target else { return }
        card.status = target
        if from == .active { card.statusBeforeActive = nil }
        if target == .done { card.doneAt = date }
        if from == .done { card.doneAt = nil }
        card.updatedAt = date
        Event.record(.cardStatus, in: context, card: card, at: date,
                     payload: ["from": .string(from.rawValue), "to": .string(target.rawValue)])
    }
}
