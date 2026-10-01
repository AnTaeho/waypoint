import Foundation

public enum SessionActivity: String, Sendable {
    case working, toolRunning, waiting, approval, idle, recent, expired, ended
    public var title: String {
        switch self {
        case .working: "응답 진행 중"
        case .toolRunning: "도구 작업 중"
        case .waiting: "입력 대기"
        case .approval: "승인 대기"
        case .idle: "활동 없음"
        case .recent: "최근 활동"
        case .expired: "추적 만료"
        case .ended: "세션 종료"
        }
    }
    public var isBusy: Bool { self == .working || self == .toolRunning || self == .recent }
}

public enum SessionActivityRules {
    private struct PendingTool: Codable { let name: String; let at: Date }
    public static let hookEvents: Set<String> = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Stop", "Interrupt", "SessionEnd", "SubagentStart", "SubagentStop"]
    public static func tools(_ session: Session) -> [String: String] {
        trackedTools(session).mapValues(\.name)
    }
    private static func trackedTools(_ session: Session) -> [String: PendingTool] {
        guard let data = session.pendingToolsData else { return [:] }
        return (try? JSONDecoder().decode([String: PendingTool].self, from: data)) ?? [:]
    }
    public static func reset(_ session: Session) {
        session.activityRaw = ""; session.activityAt = nil; session.pendingToolsData = nil; session.endReason = nil
    }

    /// 도구 호출·입력 대기 증거는 시간만으로 덮지 않는다. 응답 중/이전 세션의 공백만 idle로 표시한다.
    public static func activity(_ session: Session, now: Date, timeout: TimeInterval = SessionRules.defaultStallTimeout) -> SessionActivity {
        if session.endedAt != nil {
            let reason = session.endReason ?? (session.events ?? []).filter { $0.type == .sessionEnd }.max { $0.at < $1.at }?.payloadValues["reason"]?.stringValue
            return [SessionSweep.reasonInactive, "inactive-24h"].contains(reason ?? "") ? .expired : .ended
        }
        if session.kind == .main, (session.children ?? []).contains(where: {
            $0.endedAt == nil && [.working, .toolRunning].contains(activity($0, now: now, timeout: timeout))
        }) { return .toolRunning }
        let phase = SessionActivity(rawValue: session.activityRaw)
        if phase == .approval || phase == .waiting { return phase! }
        if !tools(session).isEmpty { return .toolRunning }
        if now.timeIntervalSince(session.lastSeenAt) > timeout { return .idle }
        return phase == .working ? .working : .recent
    }

    /// 활동 시각이 오래된 outbox는 현재 상태·병렬 도구 목록을 되돌리지 않는다.
    public static func observe(_ input: HookInput, session: Session, at: Date) {
        guard session.endedAt == nil else { return }
        var pending = trackedTools(session)
        let key = input.toolUseID ?? "name:\(input.toolName ?? "unknown")"
        if at < max(session.lastSeenAt, session.activityAt ?? .distantPast) {
            // 병렬 도구의 완료 기록은 순서가 뒤바뀌어도 해당 호출만 닫는다.
            guard input.event == "PostToolUse" || input.event == "PostToolUseFailure" else { return }
            pending = pending.filter { id, tool in
                let matches = input.toolUseID == nil ? tool.name == input.toolName : id == key
                return !matches || tool.at > at
            }
            session.pendingToolsData = pending.isEmpty ? nil : try? JSONEncoder().encode(pending)
            if pending.isEmpty && session.activityRaw == SessionActivity.toolRunning.rawValue {
                session.activityRaw = SessionActivity.working.rawValue
            }
            session.cachedState = SessionRules.state(of: session, now: session.lastSeenAt)
            return
        }
        switch input.event {
        case "SessionStart": pending = [:]; session.activityRaw = SessionActivity.waiting.rawValue
        case "UserPromptSubmit": pending = [:]; session.activityRaw = SessionActivity.working.rawValue
        case "PreToolUse":
            pending[key] = PendingTool(name: String((input.toolName ?? "도구").prefix(120)), at: at)
            session.activityRaw = (["AskUserQuestion", "request_user_input"].contains(input.toolName ?? "") ? SessionActivity.waiting : .toolRunning).rawValue
        case "PermissionRequest": session.activityRaw = SessionActivity.approval.rawValue
        case "PostToolUse", "PostToolUseFailure":
            if input.toolUseID != nil { pending[key] = nil }
            else { pending = pending.filter { $0.value.name != input.toolName } }
            session.activityRaw = SessionActivity.working.rawValue
        case "Stop", "Interrupt": pending = [:]; session.activityRaw = SessionActivity.waiting.rawValue
        case "SubagentStart": session.activityRaw = SessionActivity.working.rawValue
        default: return
        }
        session.pendingToolsData = pending.isEmpty ? nil : try? JSONEncoder().encode(pending)
        session.activityAt = at
        session.cachedState = SessionRules.state(of: session, now: at)
    }
}
