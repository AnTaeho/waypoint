import Foundation

// 모델에는 rawValue 문자열로 저장한다(프레디케이트·CloudKit 안정성).

public enum CardKind: String, Codable, Sendable, CaseIterable {
    case task, idea, bug
}

public enum CardStatus: String, Codable, Sendable, CaseIterable {
    case idea, next, active, done, archived
}

public enum CardOrigin: String, Codable, Sendable, CaseIterable {
    case claude, manual
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
}

public enum GuideSource: String, Codable, Sendable, CaseIterable {
    case app, local
}
