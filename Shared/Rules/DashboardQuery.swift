import Foundation
import SwiftData

/// 대시보드 "작업중" 한 줄 = (카드, 세션) 열린 연결 하나.
public struct DashboardRow: Identifiable {
    public let card: Card
    public let session: Session
    /// 이 줄의 세션 상태(live 또는 stalled)
    public let workState: CardWorkState
    /// 0 = 메인 세션, 1 = 부모 세션 줄 바로 아래 서브에이전트
    public let depth: Int

    public var id: String { "\(session.id)|\(card.id.uuidString)" }
}

public struct DashboardGroup: Identifiable {
    public let project: Project
    public let rows: [DashboardRow]

    public var id: UUID { project.id }
    public var hasLive: Bool { rows.contains { $0.workState == .live } }
}

/// 프로젝트 표 한 줄 집계.
public struct ProjectSummary {
    /// 작업중(live) 카드 수. 표의 "작업중" 열.
    public let liveCount: Int
    /// 열린 연결이 전부 멈춘 카드 수.
    public let stalledCount: Int
    public let nextCount: Int
    public let ideaCount: Int
    /// 이벤트·세션 활동·카드 수정 중 가장 늦은 시각. 아무것도 없으면 nil.
    public let lastActivityAt: Date?
}

public enum DashboardQuery {

    /// 모든 프로젝트(보관 제외)를 불러와 그룹을 만든다.
    public static func groups(
        in context: ModelContext,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) throws -> [DashboardGroup] {
        let projects = try context.fetch(FetchDescriptor<Project>())
        return groups(for: projects, now: now, stallTimeout: stallTimeout)
    }

    /// 열린 연결 중 끝나지 않은 세션(live·stalled)만. 줄이 없는 프로젝트와 보관된 프로젝트는 빠진다.
    /// 그룹 순서: live 줄이 있는 프로젝트 먼저, 그다음 이름순.
    public static func groups(
        for projects: [Project],
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> [DashboardGroup] {
        let groups = projects
            .filter { $0.archivedAt == nil }
            .compactMap { project -> DashboardGroup? in
                let rows = rows(for: project, now: now, stallTimeout: stallTimeout)
                return rows.isEmpty ? nil : DashboardGroup(project: project, rows: rows)
            }
        return groups.sorted { a, b in
            if a.hasLive != b.hasLive { return a.hasLive }
            let order = a.project.name.localizedStandardCompare(b.project.name)
            if order != .orderedSame { return order == .orderedAscending }
            return a.project.key < b.project.key
        }
    }

    /// 한 프로젝트의 줄. 메인 줄은 세션 시작순, 서브에이전트 줄은 부모 세션의 마지막 줄 바로 아래(depth 1).
    /// 부모 세션 줄이 없는 서브에이전트는 depth 0으로 메인 줄들 사이에 놓인다.
    public static func rows(
        for project: Project,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> [DashboardRow] {
        struct Pending {
            let card: Card
            let session: Session
            let state: CardWorkState
            let attachedAt: Date
        }

        var pending: [Pending] = []
        for session in project.sessions ?? [] {
            let state = SessionRules.state(of: session, now: now, stallTimeout: stallTimeout)
            let work: CardWorkState
            switch state {
            case .live: work = .live
            case .stalled: work = .stalled
            case .ended: continue
            }
            for link in session.openCardSessions {
                guard let card = link.card else { continue }
                pending.append(Pending(card: card, session: session, state: work, attachedAt: link.attachedAt))
            }
        }

        let sessionsWithRows = Set(pending.map { ObjectIdentifier($0.session) })
        func isNested(_ p: Pending) -> Bool {
            guard let parent = p.session.parent else { return false }
            return sessionsWithRows.contains(ObjectIdentifier(parent))
        }
        func byTime(_ a: Pending, _ b: Pending) -> Bool {
            if a.session.startedAt != b.session.startedAt { return a.session.startedAt < b.session.startedAt }
            if a.attachedAt != b.attachedAt { return a.attachedAt < b.attachedAt }
            return a.card.number < b.card.number
        }

        let top = pending.filter { !isNested($0) }.sorted(by: byTime)
        let nested = pending.filter(isNested).sorted(by: byTime)

        var result: [DashboardRow] = []
        var index = 0
        while index < top.count {
            // 같은 세션의 줄을 모두 놓은 뒤 그 세션의 서브에이전트 줄을 붙인다.
            let session = top[index].session
            while index < top.count, top[index].session === session {
                let p = top[index]
                result.append(DashboardRow(card: p.card, session: p.session, workState: p.state, depth: 0))
                index += 1
            }
            for p in nested where p.session.parent === session {
                result.append(DashboardRow(card: p.card, session: p.session, workState: p.state, depth: 1))
            }
        }
        return result
    }

    public static func summary(
        for project: Project,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> ProjectSummary {
        let cards = project.cards ?? []
        var live = 0, stalled = 0, next = 0, idea = 0
        for card in cards {
            switch CardRules.workState(of: card, now: now, stallTimeout: stallTimeout) {
            case .live: live += 1
            case .stalled: stalled += 1
            case .none: break
            }
            switch card.status {
            case .next: next += 1
            case .idea: idea += 1
            default: break
            }
        }
        // 이벤트는 훅마다 쌓이므로 전체를 읽지 않고 `lastEventAt` 캐시를 쓴다.
        let times: [Date] = [project.lastEventAt].compactMap { $0 }
            + (project.sessions ?? []).map(\.lastSeenAt)
            + cards.map(\.updatedAt)
        return ProjectSummary(
            liveCount: live,
            stalledCount: stalled,
            nextCount: next,
            ideaCount: idea,
            lastActivityAt: times.max()
        )
    }
}
