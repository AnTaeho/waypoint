import Foundation
import SwiftData

/// Waypoint에서 연 이슈·PR 하나(이벤트 `github.issue`·`github.pr`에서 읽는다).
public struct GitHubItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: GitHubKind
    public let repo: String
    public let number: Int
    public let url: String
    public var title: String
    public var state: GitHubState
    public let branch: String?
    public let projectID: UUID?
    /// 이어진 카드(「TRK-68」). 없으면 nil
    public let cardID: String?
    public let at: Date

    /// 상태를 다시 읽을 때의 열쇠
    public var key: String { "\(repo.lowercased())#\(kind.rawValue)#\(number)" }
    /// 「이슈 #12」「PR #34」
    public var label: String { "\(kind.name) #\(number)" }
}

/// 연 이슈·PR의 기록과 조회.
public enum GitHubLog {
    /// 이을 카드: 준 카드가 먼저, 없으면 그 세션의 작업중 카드가 하나일 때 그 카드.
    public static func linkedCard(explicit: Card?, session: Session?) -> Card? {
        if let explicit { return explicit }
        var seen = Set<UUID>()
        let cards = (session?.openCardSessions ?? []).compactMap(\.card)
            .filter { $0.status == .active && seen.insert($0.id).inserted }
        return cards.count == 1 ? cards[0] : nil
    }

    @discardableResult
    public static func record(_ created: GitHubCreated, project: Project, card: Card?, session: Session?,
                              at date: Date, in context: ModelContext) -> Event {
        var payload: [String: EventValue] = [
            "number": .int(created.number), "url": .string(created.url), "title": .string(created.title),
            "state": .string(created.state.rawValue), "repo": .string(created.repo),
        ]
        if let branch = created.branch { payload["branch"] = .string(branch) }
        if let session { payload["provider"] = .string(session.provider.rawValue) }
        return Event.record(created.kind.eventType, in: context, project: project, card: card, session: session,
                            at: date, payload: payload)
    }

    public static func item(_ event: Event) -> GitHubItem? {
        let kind: GitHubKind
        switch event.type {
        case .githubIssue: kind = .issue
        case .githubPR: kind = .pr
        default: return nil
        }
        let p = event.payloadValues
        guard let number = p["number"]?.intValue, let url = p["url"]?.stringValue, let repo = p["repo"]?.stringValue
        else { return nil }
        return GitHubItem(id: event.id, kind: kind, repo: repo, number: number, url: url,
                          title: p["title"]?.stringValue ?? "",
                          state: p["state"]?.stringValue.flatMap(GitHubState.init(rawValue:)) ?? .open,
                          branch: p["branch"]?.stringValue, projectID: event.project?.id,
                          cardID: event.card?.displayID, at: event.at)
    }

    /// 이 카드의 이슈·PR, 최근 것부터
    public static func items(for card: Card) -> [GitHubItem] {
        sorted((card.events ?? []).compactMap(item))
    }

    /// 이 프로젝트에서 연 것 전부, 최근 것부터
    public static func items(for project: Project) -> [GitHubItem] {
        guard let context = project.modelContext else { return sorted((project.events ?? []).compactMap(item)) }
        return items(in: context).filter { $0.projectID == project.id }
    }

    /// 모든 프로젝트의 것(상황판이 한 번에 읽는다)
    public static func items(in context: ModelContext) -> [GitHubItem] {
        let types = GitHubKind.allCases.map(\.eventType.rawValue)
        let events = (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate<Event> { types.contains($0.typeRaw) }))) ?? []
        return sorted(events.compactMap(item))
    }

    /// 「이슈 2 · PR 1」. 열린 것이 없으면 nil
    public static func openSummary(_ items: [GitHubItem]) -> String? {
        let open = items.filter(\.state.isOpen)
        guard !open.isEmpty else { return nil }
        return "이슈 \(open.filter { $0.kind == .issue }.count) · PR \(open.filter { $0.kind == .pr }.count)"
    }

    /// 카드 제목·본문·완료 조건으로 채운 초안
    public static func draft(for card: Card, kind: GitHubKind) -> GitHubDraft {
        var parts = [card.body.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        if !card.criteria.isEmpty {
            parts.append(card.criteria.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }.joined(separator: "\n"))
        }
        return GitHubDraft(kind: kind, title: card.title, body: parts.joined(separator: "\n\n"))
    }

    private static func sorted(_ items: [GitHubItem]) -> [GitHubItem] {
        items.sorted { ($0.at, $0.number) > ($1.at, $1.number) }
    }
}
