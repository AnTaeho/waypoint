import Foundation

// 모델에는 rawValue 문자열로 저장한다(프레디케이트·CloudKit 안정성).

public enum CardKind: String, Codable, Sendable, CaseIterable {
    case task, idea, bug
}

public enum CardStatus: String, Codable, Sendable, CaseIterable {
    case idea, next, active, done, archived
}

public enum CardOrigin: String, Codable, Sendable, CaseIterable {
    case claude, codex, manual
}

/// 도구의 원본 ID를 Waypoint ID로 바꾼다. 기존 Claude 기록의 ID는 유지한다.
public enum AgentProvider: String, Codable, Sendable, CaseIterable {
    case claude, codex

    public var name: String { self == .codex ? "Codex" : "Claude Code" }
    public var cardOrigin: CardOrigin { self == .codex ? .codex : .claude }

    public func sessionID(_ raw: String) -> String {
        self == .codex ? "codex:\(raw)" : raw
    }
}

public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case main, subagent
}

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case live, stalled, ended
}

public enum EventType: String, Codable, Sendable, CaseIterable {
    case sessionStart = "session.start"
    case sessionEnd = "session.end"
    case cardCreated = "card.created"
    case cardStatus = "card.status"
    case cardAttached = "card.attached"
    case cardDetached = "card.detached"
    case fileChanged = "file.changed"
    case commit = "commit"
    case note = "note"
    case guideSynced = "guide.synced"
    /// 검증 근거(명령·결과·출처). payload는 `CheckRecord`.
    case check = "check"
    /// 프로젝트 지금 상황(TRK-63, `project_status`). payload `summary`·`provider`·`sessionId`. 최신 것이 현재 상황.
    /// 옛 앱은 모르는 종류를 `note`로 읽으므로 `text` 키를 두지 않는다(옛 앱에 메모로 보이지 않게).
    case projectStatus = "project.status"
    /// 정리 안 된 작업 처리(TRK-62, `work_file`). payload `sessionId`·`outcome`(filed·dismissed)·`cardId`·`moved`.
    case sessionFiled = "session.filed"
    /// Waypoint에서 연 GitHub 이슈·PR(TRK-68). payload `number`·`url`·`title`·`state`·`repo`·`branch`(PR)·`provider`.
    case githubIssue = "github.issue"
    case githubPR = "github.pr"
}

public enum GuideSource: String, Codable, Sendable, CaseIterable {
    case app, local
}
