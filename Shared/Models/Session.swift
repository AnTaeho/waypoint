import Foundation
import SwiftData

@Model
public final class Session {
    /// Claude Code `session_id`. 중복은 코드에서 막는다.
    public var id: String = ""
    public var project: Project?
    public var kindRaw: String = SessionKind.main.rawValue
    public var parent: Session?
    @Relationship(deleteRule: .nullify, inverse: \Session.parent)
    public var children: [Session]? = []
    public var agentName: String?
    public var cwd: String = ""
    public var gitBranch: String?
    public var startedAt: Date = Date()
    public var lastSeenAt: Date = Date()
    public var endedAt: Date?
    /// 저장 캐시. 판정은 항상 `SessionRules.state(of:now:)`로 다시 계산한다.
    public var stateRaw: String = SessionState.live.rawValue

    @Relationship(deleteRule: .cascade, inverse: \CardSession.session)
    public var cardSessions: [CardSession]? = []
    @Relationship(deleteRule: .nullify, inverse: \Event.session)
    public var events: [Event]? = []

    public init(
        id: String,
        kind: SessionKind = .main,
        agentName: String? = nil,
        cwd: String = "",
        gitBranch: String? = nil,
        startedAt: Date = Date(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.agentName = agentName
        self.cwd = cwd
        self.gitBranch = gitBranch
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt ?? startedAt
    }

    public var kind: SessionKind {
        get { SessionKind(rawValue: kindRaw) ?? .main }
        set { kindRaw = newValue.rawValue }
    }

    /// 저장된 캐시 값. 화면 판정에는 쓰지 않는다.
    public var cachedState: SessionState {
        get { SessionState(rawValue: stateRaw) ?? .live }
        set { stateRaw = newValue.rawValue }
    }

    public var openCardSessions: [CardSession] {
        (cardSessions ?? []).filter { $0.detachedAt == nil }
    }
}

@Model
public final class CardSession {
    public var card: Card?
    public var session: Session?
    public var attachedAt: Date = Date()
    public var detachedAt: Date?

    public init(attachedAt: Date = Date()) {
        self.attachedAt = attachedAt
    }

    public var isOpen: Bool { detachedAt == nil }
}
