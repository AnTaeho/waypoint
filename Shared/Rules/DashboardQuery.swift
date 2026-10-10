import Foundation
import SwiftData

/// 대시보드 "작업중" 한 줄 = (카드, 세션) 열린 연결 하나, 또는 카드가 붙지 않은 끝나지 않은 메인 세션 하나(`card == nil`).
public struct DashboardRow: Identifiable {
    /// nil이면 카드 없이 도는 메인 세션 줄
    public let card: Card?
    public let session: Session
    /// 이 줄의 세션 상태(live 또는 stalled)
    public let workState: CardWorkState
    /// 0 = 메인 세션, 1 = 부모 세션 줄 바로 아래 서브에이전트
    public let depth: Int
    /// 이 카드에 세션이 연결된 시각(`CardSession.attachedAt`). 카드 없는 줄은 nil
    public let attachedAt: Date?
    /// 이 줄에 보일 기다림(승인·질문). 세션 자신의 것이거나 줄이 없는 서브에이전트의 것. 있으면 `workState`는 stalled다
    public var waiting: SessionWaiting.Shown?

    public var waitingKind: SessionWaiting.Kind? { waiting?.kind }

    public var id: String { "\(session.id)|\(card?.id.uuidString ?? "-")" }
}

public struct DashboardGroup: Identifiable {
    public let project: Project
    public let rows: [DashboardRow]

    public var id: UUID { project.id }
    public var hasLive: Bool { rows.contains { $0.workState == .live } }
}

/// 프로젝트 표 한 줄 집계.
public struct ProjectSummary {
    /// 작업중(live) 카드 수 + 카드 없이 도는 live 메인 세션 수. 표의 "작업중" 열, 사이드바 개수.
    public let liveCount: Int
    /// 열린 연결이 전부 멈춘 카드 수 + 카드 없이 멈춘 메인 세션 수.
    public let stalledCount: Int
    public let nextCount: Int
    public let ideaCount: Int
    /// 이벤트·세션 활동·카드 수정 중 가장 늦은 시각. 아무것도 없으면 nil.
    public let lastActivityAt: Date?
    /// 내 답(승인·질문)을 기다리는 세션 수(서브에이전트 포함). 사이드바 표시에 쓴다
    public var waitingCount = 0

    /// 사이드바 프로젝트 줄 오른쪽에 그릴 것 하나.
    public enum SidebarMark: Equatable, Sendable {
        case waiting(Int), live(Int), stalled(Int)
    }

    /// 내 답을 기다리는 세션이 있으면 그것부터, 다음은 작업중, 다음은 멈춤. 아무것도 없으면 nil.
    public var sidebarMark: SidebarMark? {
        if waitingCount > 0 { return .waiting(waitingCount) }
        if liveCount > 0 { return .live(liveCount) }
        if stalledCount > 0 { return .stalled(stalledCount) }
        return nil
    }
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
    /// 카드가 붙지 않은 끝나지 않은 메인 세션은 카드 없는 줄 하나로 들어간다(서브에이전트는 카드가 있을 때만 줄이 된다).
    /// 부모 세션 줄이 없는 서브에이전트(부모가 끝남)는 depth 0으로 메인 줄들 사이에 놓인다.
    public static func rows(
        for project: Project,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> [DashboardRow] {
        rows(of: openSessions(of: project), now: now, stallTimeout: stallTimeout)
    }

    /// 이미 읽은 끝나지 않은 세션으로 줄을 만든다(상황판이 같은 세션을 두 번 읽지 않게).
    static func rows(of sessions: [Session], now: Date, stallTimeout: TimeInterval) -> [DashboardRow] {
        struct Pending {
            let card: Card?
            let session: Session
            let state: CardWorkState
            let attachedAt: Date
            let waiting: SessionWaiting.Shown?
        }

        var pending: [Pending] = []
        // 끝난 세션은 줄이 되지 않는다. 상태 판정(끝난 까닭을 이벤트에서 찾을 수 있다)을 건너뛴다.
        for session in sessions {
            let state = SessionRules.state(of: session, now: now, stallTimeout: stallTimeout)
            let work: CardWorkState
            switch state {
            case .live: work = .live
            case .stalled: work = .stalled
            case .ended: continue
            }
            // 기다리는 줄은 멈춘 줄로 둔다(내 답 없이는 못 나아간다). 세션마다 한 번만 본다.
            let waiting = SessionWaiting.shown(for: session, now: now, stallTimeout: stallTimeout)
            let links = session.openCardSessions.filter { $0.card != nil }.sorted { $0.attachedAt < $1.attachedAt }
            for (index, link) in links.enumerated() {
                // 서브에이전트에게서 올린 기다림은 첫 줄에만 둔다(두 번 세지 않게).
                let shown = index == 0 || waiting?.session === session ? waiting : nil
                pending.append(Pending(card: link.card, session: session, state: shown == nil ? work : .stalled,
                                       attachedAt: link.attachedAt, waiting: shown))
            }
            if links.isEmpty, session.kind == .main,
               SessionRules.hasUnassignedWork(session, now: now, stallTimeout: stallTimeout) {
                pending.append(Pending(card: nil, session: session, state: waiting == nil ? work : .stalled,
                                       attachedAt: session.startedAt, waiting: waiting))
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
            let an = a.card?.number ?? 0, bn = b.card?.number ?? 0
            if an != bn { return an < bn }
            return a.session.id < b.session.id
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
                result.append(DashboardRow(card: p.card, session: p.session, workState: p.state, depth: 0,
                                          attachedAt: p.card == nil ? nil : p.attachedAt, waiting: p.waiting))
                index += 1
            }
            for p in nested where p.session.parent === session {
                result.append(DashboardRow(card: p.card, session: p.session, workState: p.state, depth: 1,
                                          attachedAt: p.card == nil ? nil : p.attachedAt, waiting: p.waiting))
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
        // 카드 없이 도는 메인 세션도 작업중·멈춤에 센다(대시보드 줄과 같은 기준).
        // 끝나지 않은 세션은 한 번만 읽어 기다림 수에도 쓴다.
        let sessions = openSessions(of: project)
        for session in sessions where session.kind == .main {
            guard !session.openCardSessions.contains(where: { $0.card != nil }),
                  SessionRules.hasUnassignedWork(session, now: now, stallTimeout: stallTimeout) else { continue }
            switch SessionRules.state(of: session, now: now, stallTimeout: stallTimeout) {
            case .live: live += 1
            case .stalled: stalled += 1
            case .ended: break
            }
        }
        return ProjectSummary(
            liveCount: live,
            stalledCount: stalled,
            nextCount: next,
            ideaCount: idea,
            lastActivityAt: lastActivityAt(of: project),
            waitingCount: SessionWaiting.count(sessions, now: now, stallTimeout: stallTimeout).total
        )
    }

    /// 이벤트·세션 활동·카드 수정 중 가장 늦은 시각. 아무것도 없으면 nil.
    /// 이벤트는 훅마다 쌓이므로 전체를 읽지 않고 `lastEventAt` 캐시를 쓴다. 세션도 쌓이므로 가장 늦은 것만 읽는다.
    public static func lastActivityAt(of project: Project) -> Date? {
        let times: [Date] = [project.lastEventAt, latestSessionActivity(of: project)].compactMap { $0 }
            + (project.cards ?? []).map(\.updatedAt)
        return times.max()
    }

    /// 이 프로젝트의 끝나지 않은 세션(순서 없음). 끝난 세션은 계속 쌓이므로(큰 기록에서 1,600개) 관계(`project.sessions`)
    /// 전체를 돌지 않고 질의로 좁힌다(TRK-66). 질의는 저장 전 변경(새 세션, 끝남·되살림)도 본다.
    static func openSessions(of project: Project) -> [Session] {
        guard let context = project.modelContext else { return (project.sessions ?? []).filter { $0.endedAt == nil } }
        let projectID = project.id
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.endedAt == nil && $0.project?.id == projectID
        })
        // 상태 판정이 하위 세션을 읽는다(서브에이전트 100개가 넘는 세션이 있다). 하나씩 읽지 않게 같이 가져온다.
        descriptor.relationshipKeyPathsForPrefetching = [\.children]
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.project === project }
    }

    /// 세션 중 가장 늦은 `lastSeenAt`. 저장소에서는 가장 늦은 몇 개만 읽고, 저장 전 바뀐 세션은 메모리 값으로 더한다
    /// (저장소 값이 옛 값이거나 다른 프로젝트로 옮겨 가는 중이어도 맞게).
    static func latestSessionActivity(of project: Project) -> Date? {
        guard let context = project.modelContext else { return (project.sessions ?? []).map(\.lastSeenAt).max() }
        let pending = (context.insertedModelsArray + context.changedModelsArray).compactMap { $0 as? Session }
        let projectID = project.id
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.project?.id == projectID },
                                                  sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)])
        descriptor.fetchLimit = pending.count + 1
        let stored = (try? context.fetch(descriptor)) ?? []
        return (stored + pending).filter { $0.project === project && !$0.isDeleted }.map(\.lastSeenAt).max()
    }
}
