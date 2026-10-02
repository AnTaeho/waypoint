import Foundation
import SwiftData

public enum SessionFormat {

    /// 도구·대기·활동 없음의 원인을 표시한다. 오래된 세션에도 미확인 상태를 실행 중으로 단정하지 않는다.
    public static func activityText(_ session: Session, now: Date) -> String {
        let activity = SessionActivityRules.activity(session, now: now)
        let since = session.activityAt ?? session.lastSeenAt
        if activity == .toolRunning {
            let names = Set(SessionActivityRules.tools(session).values).sorted()
            let detail = names.isEmpty ? "하위 작업" : names.prefix(2).joined(separator: ", ")
            return "\(activity.title) · \(detail)"
        }
        if activity == .waiting || activity == .approval || activity == .idle {
            return "\(activity.title) \(TimeFormat.elapsed(from: activity == .idle ? session.lastSeenAt : since, to: now))"
        }
        return activity.title
    }

    /// main → 「sess·7f2a」, subagent → 「↳ test-writer」(이름이 없으면 main과 같은 꼴).
    public static func label(kind: SessionKind, id: String, agentName: String?) -> String {
        if kind == .subagent, let agentName, !agentName.isEmpty {
            return "↳ \(agentName)"
        }
        return "sess·\(id.prefix(4))"
    }

    public static func label(for session: Session) -> String {
        let text = label(kind: session.kind, id: session.sourceID, agentName: session.agentName)
        return session.provider == .codex ? "Codex · \(text)" : text
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
        state: CardWorkState, lastPromptAt: Date?, attachedAt: Date?, lastSeenAt: Date, now: Date,
        session: Session? = nil
    ) -> String? {
        if let session { return activityText(session, now: now) }
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
        guard let context = session.modelContext else {
            return fileName(of: (card.events ?? []).filter { $0.type == .fileChanged && $0.session === session }
                .max { $0.at < $1.at })
        }
        let raw = EventType.fileChanged.rawValue
        let cardID = card.persistentModelID, sessionID = session.persistentModelID
        let predicate = #Predicate<Event> {
            $0.typeRaw == raw && $0.card?.persistentModelID == cardID && $0.session?.persistentModelID == sessionID
        }
        let latest = latestEvent(in: context, predicate) { event in
            event.type == .fileChanged && event.card === card && event.session === session
        }
        return fileName(of: latest)
    }

    /// 카드 없는 세션 줄: 이 세션과 그 서브에이전트가 카드 없이 남긴 가장 최근 `file.changed`의 파일 이름. 없으면 nil.
    public static func recentFileName(session: Session) -> String? {
        let owners = [session] + (session.children ?? [])
        guard let context = session.modelContext else {
            let events: [Event] = owners.flatMap { $0.events ?? [] }
            return fileName(of: events.filter { $0.type == .fileChanged && $0.card == nil }.max { $0.at < $1.at })
        }
        let raw = EventType.fileChanged.rawValue
        let sessionID = session.persistentModelID
        let ownPredicate = #Predicate<Event> {
            $0.typeRaw == raw && $0.card == nil && $0.session?.persistentModelID == sessionID
        }
        let own = latestEvent(in: context, ownPredicate) { event in
            event.type == .fileChanged && event.card == nil && event.session === session
        }
        // 서브에이전트가 여럿이어도(100개 넘는 세션이 있다) 질의 하나로 본다.
        let children = (session.children ?? []).map(\.persistentModelID)
        let childPredicate = #Predicate<Event> { event in
            event.typeRaw == raw && event.card == nil
                && (event.session.flatMap { children.contains($0.persistentModelID) } ?? false)
        }
        let child = children.isEmpty ? nil : latestEvent(in: context, childPredicate) { event in
            event.type == .fileChanged && event.card == nil && event.session?.parent === session
        }
        // 같은 시각이면 세션 자신의 것(전 구현은 세션 → 서브에이전트 순으로 돌았다)
        guard let child, child.at > (own?.at ?? .distantPast) else { return fileName(of: own) }
        return fileName(of: child)
    }

    /// 조건에 맞는 이벤트 중 가장 늦은 것. 긴 세션은 이벤트가 1,000건을 넘는다. 대시보드가 세션을 매번 새로 읽으므로
    /// (TRK-66) 관계를 다 읽으면 그릴 때마다 이벤트를 하나씩 다시 읽는다. 저장소에서는 가장 늦은 몇 건만 읽고, 저장 전에 넣거나
    /// 바꾼 이벤트는 메모리 값(`matches`)으로 다시 본다.
    static func latestEvent(in context: ModelContext, _ predicate: Predicate<Event>,
                            matches: (Event) -> Bool) -> Event? {
        let pending = (context.insertedModelsArray + context.changedModelsArray).compactMap { $0 as? Event }
        var descriptor = FetchDescriptor<Event>(predicate: predicate, sortBy: [SortDescriptor(\.at, order: .reverse)])
        descriptor.fetchLimit = pending.count + 1
        let stored = (try? context.fetch(descriptor)) ?? []
        return (stored + pending).filter { !$0.isDeleted && matches($0) }.max { $0.at < $1.at }
    }

    private static func fileName(of event: Event?) -> String? {
        guard let path = event?.payloadValues["path"]?.stringValue, !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }
}
