import Foundation
import SwiftData

/// 프로젝트 보드의 칸. 보관(archived) 카드는 어느 칸에도 없다.
public enum BoardColumn: String, CaseIterable, Sendable, Hashable {
    case idea, next, active, done

    /// 이 칸에 카드를 떨어뜨렸을 때 옮겨 갈 상태.
    public var status: CardStatus {
        switch self {
        case .idea: .idea
        case .next: .next
        case .active: .active
        case .done: .done
        }
    }

    /// 사용자가 끌어다 놓을 수 있는 칸인지. 작업중은 세션이 붙어야만 들어간다.
    public var acceptsDrop: Bool { self != .active }
}

/// 보드 칸 안의 카드 한 장. depth 1은 같은 칸의 부모 카드 아래 들여 쓴 하위 카드.
public struct BoardItem: Identifiable {
    public let card: Card
    public let depth: Int

    public var id: UUID { card.id }
}

/// 카드 한 장의 누적 작업 집계.
public struct CardWorkStats: Equatable, Sendable {
    /// 이 카드에 붙었던 서로 다른 메인 세션 수
    public let sessionCount: Int
    /// 서브에이전트 세션 수(아래 `stats` 설명 참고)
    public let subagentCount: Int
    public let commitCount: Int
}

public enum BoardQuery {
    /// 완료 칸에 보이는 기간(7일).
    public static let doneWindow: TimeInterval = 7 * 24 * 3600

    /// 칸별 카드. 순서:
    /// - 아이디어: 만든 시각 최신순
    /// - 다음: 카드 번호순
    /// - 작업중: 연결된 시각순, 같은 칸에 부모가 있는 하위 카드는 부모 바로 아래(depth 1)
    /// - 완료: `now - doneWindow` 이후 완료된 것만, 완료 시각 최신순
    public static func columns(for project: Project, now: Date) -> [BoardColumn: [BoardItem]] {
        let cards = project.cards ?? []
        let ideas = cards.filter { $0.status == .idea }
            .sorted { ($0.createdAt, $0.number) > ($1.createdAt, $1.number) }
        let next = cards.filter { $0.status == .next }
            .sorted { $0.number < $1.number }
        let since = now.addingTimeInterval(-doneWindow)
        let done = cards.filter { $0.status == .done && ($0.doneAt ?? .distantPast) >= since }
            .sorted { ($0.doneAt ?? .distantPast, $0.number) > ($1.doneAt ?? .distantPast, $1.number) }
        return [
            .idea: ideas.map { BoardItem(card: $0, depth: 0) },
            .next: next.map { BoardItem(card: $0, depth: 0) },
            .active: nested(cards.filter { $0.status == .active }),
            .done: done.map { BoardItem(card: $0, depth: 0) },
        ]
    }

    /// 부모가 같은 목록에 있으면 부모 아래에 붙인다. 한 단계만 들여 쓴다.
    static func nested(_ cards: [Card]) -> [BoardItem] {
        func attachedAt(_ card: Card) -> Date {
            card.openCardSessions.map(\.attachedAt).min() ?? card.updatedAt
        }
        let sorted = cards.sorted { (attachedAt($0), $0.number) < (attachedAt($1), $1.number) }
        let ids = Set(sorted.map(\.id))
        func isChild(_ card: Card) -> Bool {
            guard let parent = card.parent else { return false }
            return ids.contains(parent.id)
        }
        var result: [BoardItem] = []
        for card in sorted where !isChild(card) {
            result.append(BoardItem(card: card, depth: 0))
            for child in sorted where child.parent?.id == card.id {
                result.append(BoardItem(card: child, depth: 1))
            }
        }
        // 부모가 목록에 있지만 그 부모가 다시 하위 카드인 경우(손주) — 한 단계만 들여 쓰고 빠뜨리지 않는다.
        let placed = Set(result.map(\.card.id))
        for card in sorted where !placed.contains(card.id) {
            result.append(BoardItem(card: card, depth: 1))
        }
        return result
    }

    /// 카드를 `column`에 떨어뜨릴 수 있는지. 받는 칸이 아니거나 이미 그 상태면 false.
    public static func canDrop(_ card: Card, on column: BoardColumn) -> Bool {
        column.acceptsDrop && card.status != column.status
    }

    /// 보드에서 끌어 놓은 카드를 옮긴다. 옮겼으면 true. 저장은 호출 쪽에서 한다.
    @discardableResult
    public static func drop(_ card: Card, on column: BoardColumn, at date: Date, in context: ModelContext) -> Bool {
        guard canDrop(card, on: column) else { return false }
        do {
            try CardLifecycle.move(card, to: column.status, at: date, in: context)
            return true
        } catch {
            return false
        }
    }

    /// 카드에 표시할 대표 연결: 열린 연결 중 live 세션 → stalled 세션 순, 같으면 먼저 붙은 것.
    public static func primaryLink(
        of card: Card,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> CardSession? {
        func rank(_ link: CardSession) -> Int {
            guard let session = link.session else { return 3 }
            switch SessionRules.state(of: session, now: now, stallTimeout: stallTimeout) {
            case .live: return 0
            case .stalled: return 1
            case .ended: return 2
            }
        }
        return card.openCardSessions
            .filter { $0.session != nil }
            .min { (rank($0), $0.attachedAt) < (rank($1), $1.attachedAt) }
    }

    /// 세션 수는 이 카드에 붙었던 메인 세션, 서브에이전트 수는 이 카드에 직접 붙었거나
    /// 이 카드에 붙은 메인 세션에서 갈라진 서브에이전트 세션(중복 없이).
    public static func stats(of card: Card) -> CardWorkStats {
        var main = Set<String>(), sub = Set<String>()
        for link in card.cardSessions ?? [] {
            guard let session = link.session else { continue }
            switch session.kind {
            case .main:
                main.insert(session.id)
                for child in session.children ?? [] where child.kind == .subagent {
                    sub.insert(child.id)
                }
            case .subagent:
                sub.insert(session.id)
            }
        }
        let commits = (card.events ?? []).filter { $0.type == .commit }.count
        return CardWorkStats(sessionCount: main.count, subagentCount: sub.count, commitCount: commits)
    }
}
