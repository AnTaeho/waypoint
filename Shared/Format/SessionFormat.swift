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

    /// 카드 없는 세션의 제목 자리에 요청 문장이 없을 때 쓰는 글.
    public static let noCardTitle = "카드 없음"
    /// 제목 자리에 넘기는 요청 문장 앞부분의 최대 길이(문자 단위). 화면은 줄 수로 다시 자른다.
    public static let promptPreviewLimit = 160

    /// 카드 없는 세션 제목 자리의 요청 문장: 줄바꿈·연속 공백을 공백 하나로 모아 한 줄로 만들고
    /// 앞 160자(넘으면 끝에 「…」). 비었거나 공백뿐이면 nil(화면은 `noCardTitle`).
    public static func promptPreview(_ prompt: String?) -> String? {
        guard let prompt else { return nil }
        let line = prompt.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        guard line.count > promptPreviewLimit else { return line }
        return String(line.prefix(promptPreviewLimit)) + "…"
    }

    /// 카드 없는 세션의 제목 자리 글과 그것이 요청 문장인지(false면 `noCardTitle` — 흐리게 보인다).
    public static func noCardTitle(prompt: String?) -> (text: String, isPrompt: Bool) {
        guard let preview = promptPreview(prompt) else { return (noCardTitle, false) }
        return (preview, true)
    }

    /// 작업중 줄·타일 오른쪽 경과(대시보드·보드 타일·iPhone). live면 카드 줄(`attachedAt` 있음)은 카드에 연결된
    /// 시각부터, 카드 없는 줄은 마지막 요청 시각(`lastPromptAt`)부터 「38분」(1분 미만 「방금」). 카드 없는 줄에
    /// 요청 시각이 없으면 nil(비워 둔다). stalled면 어느 줄이든 「멈춤 22분」(`lastSeenAt`부터). none은 nil.
    public static func rowElapsed(
        state: CardWorkState, lastPromptAt: Date?, attachedAt: Date?, lastSeenAt: Date, now: Date
    ) -> String? {
        switch state {
        case .live:
            guard let start = attachedAt ?? lastPromptAt else { return nil }
            return TimeFormat.elapsed(from: start, to: now)
        case .stalled:
            return "멈춤 \(TimeFormat.elapsed(from: lastSeenAt, to: now))"
        case .none:
            return nil
        }
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
