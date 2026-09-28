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
    /// 이 세션을 돌리는 Claude Code 프로세스 PID(훅 스크립트가 보낸 값). 메인 세션에만 기록한다.
    /// `SessionEnd`가 오지 않고 프로세스가 사라진 세션을 끝내는 데 쓴다(`SessionSweep`).
    public var claudePid: Int?
    /// 이 세션의 대화에 `Waypoint:` 블록을 넣어 준 프로젝트 키(`SessionStart`나 늦은 `UserPromptSubmit` 주입).
    /// nil이거나 지금 프로젝트 키와 다르면 다음 `UserPromptSubmit`에 블록을 한 번 준다(SPEC 5장 「늦은 주입」). 메인 세션만.
    public var contextProjectKey: String?
    /// 메인 세션의 마지막 사용자 요청 문장(`UserPromptSubmit`의 `prompt`, 앞뒤 공백 정리 후 300자까지).
    /// 자동으로 들어온 메시지(`<agent-message …>` 등)와 서브에이전트 훅은 넣지 않는다(`HookParsing.userPrompt`).
    /// 카드 없는 세션 줄·타일의 제목 자리에 쓴다.
    public var lastPrompt: String?
    /// `lastPrompt`를 적은 훅 시각. 카드 없는 세션 줄·타일의 경과를 여기서 잰다(`SessionFormat.rowElapsed`).
    /// `lastPrompt`와 늘 함께 바뀐다. 이 값이 생기기 전에 받은 요청은 nil로 남는다.
    public var lastPromptAt: Date?
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
