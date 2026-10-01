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
    public static func detach(_ card: Card, _ session: Session, at date: Date, in context: ModelContext, reason: String? = nil) {
        let links = card.openCardSessions.filter { $0.session === session }
        guard !links.isEmpty else { return }
        for link in links { link.detachedAt = date }
        Event.record(.cardDetached, in: context, card: card, session: session, at: date,
                     payload: ["sessionId": .string(session.id)].merging(reason.map { ["reason": .string($0)] } ?? [:]) { _, new in new })

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
    public static func detachAll(_ session: Session, at date: Date, in context: ModelContext, reason: String? = nil) {
        let cards = session.openCardSessions.compactMap(\.card)
        var seen = Set<ObjectIdentifier>()
        for card in cards where seen.insert(ObjectIdentifier(card)).inserted {
            detach(card, session, at: date, in: context, reason: reason)
        }
        session.endedAt = date
        session.cachedState = .ended
    }

    /// 카드 상태를 active가 아닌 것으로 바꾼다: 앱 드래그·「완료로 옮기기」·iPhone 분류·MCP `card_update`가 모두 여기로 온다.
    /// active로는 못 옮긴다. done 진입 시 doneAt 설정, done에서 나오면 doneAt nil. active에서 나오면 statusBeforeActive를 지운다.
    /// 카드의 열린 세션 연결(서브에이전트 포함)은 모두 닫는다(`closeOpenLinks`, 상태 복귀 없음).
    /// 불변식: 열린 연결이 있으면 카드는 active다. 같은 상태로 옮기면 아무 일도 없다.
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
        closeOpenLinks(of: card, at: date, reason: reasonMoved, in: context)
    }

    /// `card.detached` payload의 `reason`: 카드를 active 밖으로 옮겨 연결을 닫았다.
    public static let reasonMoved = "card-moved"
    /// `card.detached` payload의 `reason`: 점검에서 active가 아닌 카드의 열린 연결을 찾아 닫았다.
    public static let reasonStatusNotActive = "status-not-active"

    /// 카드의 열린 연결을 모두 닫고 세션마다 `card.detached`(`sessionId`, `reason`)를 남긴다.
    /// `detach`와 달리 카드 상태·`statusBeforeActive`·`updatedAt`은 건드리지 않는다(새 상태는 이미 정해졌다).
    /// 닫은 연결 수.
    @discardableResult
    static func closeOpenLinks(of card: Card, at date: Date, reason: String, in context: ModelContext) -> Int {
        let links = card.openCardSessions
        guard !links.isEmpty else { return 0 }
        var seen = Set<ObjectIdentifier>()
        for link in links {
            link.detachedAt = date
            guard let session = link.session, seen.insert(ObjectIdentifier(session)).inserted else { continue }
            Event.record(.cardDetached, in: context, card: card, session: session, at: date,
                         payload: ["sessionId": .string(session.id), "reason": .string(reason)])
        }
        return links.count
    }

    /// 닫아야 할 어긋난 연결인지. 순수 판정: 열린 연결인데 카드가 active가 아니다.
    /// (앞의 불변식이 생기기 전 데이터, 또는 iPhone에서 옮긴 카드를 CloudKit으로 받은 경우)
    public static func isStrayLink(cardStatus: CardStatus, detachedAt: Date?) -> Bool {
        detachedAt == nil && cardStatus != .active
    }

    /// 카드가 active가 아닌데 열린 연결을 모두 닫는다(`reason: status-not-active`). 앱 점검(시작 직후·60초마다·CloudKit 가져오기 뒤)에서 부른다.
    /// 카드 상태·`updatedAt`은 그대로 둔다. 닫은 연결 수. 저장은 호출 쪽에서 한다.
    @discardableResult
    public static func closeStrayLinks(at date: Date, in context: ModelContext) -> Int {
        let open = FetchDescriptor<CardSession>(predicate: #Predicate<CardSession> { $0.detachedAt == nil })
        let links = (try? context.fetch(open)) ?? []
        var cards: [Card] = []
        var seen = Set<ObjectIdentifier>()
        for link in links {
            guard let card = link.card,
                  isStrayLink(cardStatus: card.status, detachedAt: link.detachedAt),
                  seen.insert(ObjectIdentifier(card)).inserted
            else { continue }
            cards.append(card)
        }
        return cards.reduce(0) { $0 + closeOpenLinks(of: $1, at: date, reason: reasonStatusNotActive, in: context) }
    }
}
