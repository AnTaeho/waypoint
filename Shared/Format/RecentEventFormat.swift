import Foundation

/// 최근 기록 한 줄의 앞 표시.
public enum RecentEventMarker: String, Sendable, Hashable {
    case active, done, idea, next, commit, guide
}

/// 최근 기록 한 줄. `subject`는 카드 ID(모노) 또는 지침 문서의 프로젝트 이름.
public struct RecentEventLine: Sendable, Hashable {
    public let marker: RecentEventMarker
    public let subject: String?
    public let subjectIsCardID: Bool
    public let text: String
    /// 시각 옆에 붙는 짧은 사실(세션 표시 등). 없으면 nil.
    public let detail: String?
    public let at: Date
}

public enum RecentEventFormat {

    /// 최근 기록에 보이는 이벤트 종류. 나머지는 목록에서 뺀다.
    public static let shownTypes: [EventType] = [.cardStatus, .cardCreated, .commit, .guideSynced]

    public static func statusName(_ status: CardStatus) -> String {
        switch status {
        case .idea: "아이디어"
        case .next: "다음"
        case .active: "작업중"
        case .done: "완료"
        case .archived: "보관"
        }
    }

    /// 보일 이벤트면 한 줄을, 아니면 nil.
    public static func line(for event: Event) -> RecentEventLine? {
        let payload = event.payloadValues
        let cardID = event.card?.displayID
        switch event.type {
        case .cardStatus:
            // 작업중·완료로 바뀐 것만. 연결이 끊겨 돌아간 상태 등은 뺀다.
            guard let to = payload["to"]?.stringValue.flatMap(CardStatus.init(rawValue:)) else { return nil }
            let marker: RecentEventMarker
            switch to {
            case .active: marker = .active
            case .done: marker = .done
            default: return nil
            }
            let detail = to == .active ? event.session.map(SessionFormat.label(for:)) : nil
            return RecentEventLine(marker: marker, subject: cardID, subjectIsCardID: true,
                                   text: statusName(to), detail: detail, at: event.at)
        case .cardCreated:
            let title = event.card?.title ?? ""
            let status = payload["status"]?.stringValue.flatMap(CardStatus.init(rawValue:))
            let isIdea = event.card?.kind == .idea || status == .idea
            return RecentEventLine(marker: isIdea ? .idea : .next, subject: cardID, subjectIsCardID: true,
                                   text: "\(isIdea ? "아이디어" : "새 카드") · \(title)", detail: nil, at: event.at)
        case .commit:
            guard let hash = payload["hash"]?.stringValue, !hash.isEmpty else { return nil }
            return RecentEventLine(marker: .commit, subject: cardID, subjectIsCardID: true,
                                   text: "커밋 \(hash.prefix(7))", detail: nil, at: event.at)
        case .guideSynced:
            guard let relPath = payload["relPath"]?.stringValue, !relPath.isEmpty else { return nil }
            let name = (relPath as NSString).lastPathComponent
            return RecentEventLine(marker: .guide, subject: event.project?.name, subjectIsCardID: false,
                                   text: "\(name) 바뀜", detail: nil, at: event.at)
        default:
            return nil
        }
    }

    public static let defaultLimit = 15
    /// 최근 기록에 보이는 기간(7일).
    public static let defaultWindow: TimeInterval = 7 * 24 * 3600

    /// 최신순으로 보일 줄만 `limit`개. `now - window`보다 오래된 것과 보관된 프로젝트의 이벤트는 뺀다.
    public static func lines(
        from events: [Event],
        now: Date,
        window: TimeInterval = defaultWindow,
        limit: Int = defaultLimit
    ) -> [RecentEventLine] {
        let since = now.addingTimeInterval(-window)
        return events
            .filter { $0.at >= since && $0.project?.archivedAt == nil }
            .sorted { $0.at > $1.at }
            .lazy
            .compactMap(line(for:))
            .prefix(limit)
            .map { $0 }
    }
}
