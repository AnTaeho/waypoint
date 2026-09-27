import Foundation
import SwiftData

public struct Criterion: Codable, Sendable, Hashable {
    public var text: String
    public var isDone: Bool

    public init(_ text: String, isDone: Bool = false) {
        self.text = text
        self.isDone = isDone
    }
}

@Model
public final class Card {
    public var id: UUID = UUID()
    public var project: Project?
    public var number: Int = 0
    public var title: String = ""
    /// markdown
    public var body: String = ""
    public var kindRaw: String = CardKind.task.rawValue
    public var statusRaw: String = CardStatus.idea.rawValue
    public var parent: Card?
    @Relationship(deleteRule: .nullify, inverse: \Card.parent)
    public var children: [Card]? = []
    public var criteria: [Criterion] = []
    public var originRaw: String = CardOrigin.manual.rawValue
    public var originSessionId: String?
    public var nextSessionNote: String?
    /// 세션이 붙어 active가 되기 직전 상태(raw). 마지막 연결이 떨어지면 여기로 돌아간다.
    public var statusBeforeActive: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var doneAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \CardSession.card)
    public var cardSessions: [CardSession]? = []
    @Relationship(deleteRule: .nullify, inverse: \Event.card)
    public var events: [Event]? = []

    public init(
        number: Int,
        title: String,
        body: String = "",
        kind: CardKind = .task,
        status: CardStatus = .idea,
        origin: CardOrigin = .manual,
        originSessionId: String? = nil,
        criteria: [Criterion] = [],
        createdAt: Date = Date()
    ) {
        self.number = number
        self.title = title
        self.body = body
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.originRaw = origin.rawValue
        self.originSessionId = originSessionId
        self.criteria = criteria
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .task }
        set { kindRaw = newValue.rawValue }
    }

    /// 직접 쓰기보다 `CardLifecycle.move`를 쓴다(이벤트·doneAt 처리).
    public var status: CardStatus {
        get { CardStatus(rawValue: statusRaw) ?? .idea }
        set { statusRaw = newValue.rawValue }
    }

    public var origin: CardOrigin {
        get { CardOrigin(rawValue: originRaw) ?? .manual }
        set { originRaw = newValue.rawValue }
    }

    /// "LDG-14"
    public var displayID: String {
        "\(project?.key ?? "?")-\(number)"
    }

    /// 아직 떨어지지 않은 세션 연결.
    public var openCardSessions: [CardSession] {
        (cardSessions ?? []).filter { $0.detachedAt == nil }
    }

    public var doneCriteriaCount: Int { criteria.filter(\.isDone).count }
}
