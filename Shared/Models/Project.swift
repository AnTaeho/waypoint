import Foundation
import SwiftData

@Model
public final class Project {
    public var id: UUID = UUID()
    /// 카드 키(2–5 대문자). 중복은 코드에서 막는다(CloudKit이라 unique 속성 불가).
    public var key: String = ""
    public var name: String = ""
    public var summary: String = ""
    public var rootPath: String = ""
    public var stack: [String] = []
    public var nextCardNumber: Int = 1
    public var createdAt: Date = Date()
    public var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Card.project)
    public var cards: [Card]? = []
    @Relationship(deleteRule: .cascade, inverse: \Session.project)
    public var sessions: [Session]? = []
    @Relationship(deleteRule: .cascade, inverse: \Event.project)
    public var events: [Event]? = []
    @Relationship(deleteRule: .cascade, inverse: \GuideDoc.project)
    public var guideDocs: [GuideDoc]? = []

    public init(
        key: String,
        name: String,
        summary: String = "",
        rootPath: String = "",
        stack: [String] = [],
        createdAt: Date = Date()
    ) {
        self.key = key
        self.name = name
        self.summary = summary
        self.rootPath = rootPath
        self.stack = stack
        self.createdAt = createdAt
    }

    /// 다음 번호로 카드를 만들어 context에 넣고 `nextCardNumber`를 1 올린다.
    /// 이벤트는 남기지 않는다(호출 쪽에서 `card.created`를 기록).
    @discardableResult
    public func makeCard(
        in context: ModelContext,
        title: String,
        kind: CardKind = .task,
        status: CardStatus = .idea,
        body: String = "",
        origin: CardOrigin = .manual,
        originSessionId: String? = nil,
        parent: Card? = nil,
        criteria: [Criterion] = [],
        at date: Date = Date()
    ) -> Card {
        let card = Card(
            number: nextCardNumber,
            title: title,
            body: body,
            kind: kind,
            status: status,
            origin: origin,
            originSessionId: originSessionId,
            criteria: criteria,
            createdAt: date
        )
        context.insert(card)
        card.project = self
        card.parent = parent
        if status == .done { card.doneAt = date }
        nextCardNumber += 1
        return card
    }
}
