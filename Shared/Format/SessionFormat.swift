import Foundation

public enum SessionFormat {

    /// main → 「sess·7f2a」, subagent → 「↳ test-writer」(이름이 없으면 main과 같은 꼴).
    public static func label(kind: SessionKind, id: String, agentName: String?) -> String {
        if kind == .subagent, let agentName, !agentName.isEmpty {
            return "↳ \(agentName)"
        }
        return "sess·\(id.prefix(4))"
    }

    public static func label(for session: Session) -> String {
        label(kind: session.kind, id: session.id, agentName: session.agentName)
    }

    /// 이 카드·세션의 가장 최근 `file.changed` 경로의 파일 이름. 없으면 nil.
    public static func recentFileName(card: Card, session: Session) -> String? {
        let latest = (card.events ?? [])
            .filter { $0.type == .fileChanged && $0.session === session }
            .max { $0.at < $1.at }
        return fileName(of: latest)
    }

    /// 카드 없는 세션 줄: 이 세션과 그 서브에이전트가 카드 없이 남긴 가장 최근 `file.changed`의 파일 이름. 없으면 nil.
    public static func recentFileName(session: Session) -> String? {
        var sessions: [Session] = [session]
        sessions.append(contentsOf: session.children ?? [])
        var latest: Event?
        for event in sessions.flatMap({ $0.events ?? [] })
        where event.type == .fileChanged && event.card == nil && event.at > (latest?.at ?? .distantPast) {
            latest = event
        }
        return fileName(of: latest)
    }

    private static func fileName(of event: Event?) -> String? {
        guard let path = event?.payloadValues["path"]?.stringValue, !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }
}
