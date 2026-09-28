import Foundation

/// iPhone 「방금 기록된 아이디어」: 최근에 생긴, 아직 분류하지 않은 아이디어 카드.
public enum IdeaInbox {
    /// 기본 7일.
    public static let defaultWindow: TimeInterval = 7 * 24 * 60 * 60

    /// status가 idea이고 `now - window` 이후에 만들어진 카드. 보관된 프로젝트·프로젝트 없는 카드는 뺀다.
    /// 새것부터, 같은 시각이면 표시 ID순.
    public static func recent(
        _ cards: [Card], now: Date, window: TimeInterval = defaultWindow
    ) -> [Card] {
        let since = now.addingTimeInterval(-window)
        return cards
            .filter { card in
                guard let project = card.project, project.archivedAt == nil else { return false }
                return card.status == .idea && card.createdAt >= since
            }
            .sorted { a, b in
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
                return a.displayID < b.displayID
            }
    }
}
