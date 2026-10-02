import Foundation

/// 지침 파일을 읽는 도구의 끝나지 않은 세션 수. 고친 내용은 그 세션에 바로 반영되지 않을 수 있어 사실만 보인다.
public enum GuidanceOpenSessions {

    /// 끝나지 않은 메인 세션 중 이 출처를 읽는 것: 도구가 같고, 전역이면 모두, 아니면 걸리는 프로젝트의 세션.
    public static func count(for source: GuidanceSource, sessions: [Session]) -> Int {
        let provider: AgentProvider = source.tool == .codex ? .codex : .claude
        let keys = Set(source.appliesTo)
        return sessions.filter { session in
            guard session.kind == .main, session.endedAt == nil, session.provider == provider else { return false }
            if source.scope == .global { return true }
            guard let key = session.project?.key else { return false }
            return keys.contains(key)
        }.count
    }

    /// 「열린 Claude 세션 3」. 없으면 nil.
    public static func label(for source: GuidanceSource, count: Int) -> String? {
        guard count > 0 else { return nil }
        return "열린 \(source.tool == .codex ? "Codex" : "Claude") 세션 \(count)"
    }
}
