import Foundation
import SwiftData

/// 훅 한 건을 기록으로 바꾼다(SPEC 5장). 서버와 outbox 흡수가 같은 것을 쓴다.
/// 넘겨받은 context가 속한 액터(앱에서는 메인 액터)에서만 부른다. Sendable이 아니다.
public final class HookProcessor {
    public let context: ModelContext
    public var stallTimeout: TimeInterval
    /// 프로젝트 매칭에 쓰는 홈 폴더(`~` 펼치기). 테스트에서 바꾼다.
    public var home: String
    /// cwd → git 브랜치. 테스트에서 바꾼다.
    public var gitBranch: (String) -> String?

    /// `PreToolUse(Agent)`에서 올려 두고 `SubagentStart`에서 꺼내는 대기 항목. 메모리에만 둔다.
    struct PendingSpawn {
        let agentType: String?
        let cardNumber: Int?
        let at: Date
    }
    /// 부모 세션 ID → 먼저 올린 순
    var pendingSpawns: [String: [PendingSpawn]] = [:]
    /// 대기 항목이 짝을 기다리는 시간(10분). 넘으면 버린다.
    public static let pendingLifetime: TimeInterval = 10 * 60
    /// `subagent_type`을 안 준 Agent 호출의 기본 에이전트 종류(문서 기준).
    public static let defaultAgentType = "general-purpose"

    public init(
        context: ModelContext,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout,
        home: String = NSHomeDirectory(),
        gitBranch: @escaping (String) -> String? = { GitInfo.branch(at: $0) }
    ) {
        self.context = context
        self.stallTimeout = stallTimeout
        self.home = home
        self.gitBranch = gitBranch
    }

    /// 훅 본문(JSON)을 처리하고 저장한다. SessionStart면 주입할 텍스트를, 아니면 nil.
    /// 읽을 수 없는 본문은 무시한다(nil).
    @discardableResult
    public func handle(event: String?, json: Data, at date: Date) -> String? {
        guard let input = HookInput(event: event, json: json) else { return nil }
        return handle(input, at: date)
    }

    @discardableResult
    public func handle(_ input: HookInput, at date: Date) -> String? {
        let result = process(input, at: date)
        do {
            try context.save()
        } catch {
            context.rollback()
        }
        return result
    }

    func process(_ input: HookInput, at date: Date) -> String? {
        switch input.event {
        case "SessionStart":
            return sessionStart(input, at: date)
        case "UserPromptSubmit", "Stop":
            heartbeat(input, at: date)
        case "PreToolUse":
            preToolUse(input, at: date)
        case "SubagentStart":
            subagentStart(input, at: date)
        case "PostToolUse":
            postToolUse(input, at: date)
        case "SubagentStop":
            subagentStop(input, at: date)
        case "SessionEnd":
            sessionEnd(input, at: date)
        default:
            break
        }
        return nil
    }

    // MARK: - 조회·생성

    func fetchSession(_ id: String) -> Session? {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func matchProject(_ cwd: String) -> Project? {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return ProjectMatcher.project(for: cwd, in: projects, home: home)
    }

    /// 메인 세션. 없으면 `create`일 때 cwd로 프로젝트를 찾아 만든다(등록 안 된 폴더면 nil).
    /// 끝난 세션은 그 뒤 시각의 훅이 오면(`create`일 때) 다시 살린다. 끝난 시각 이전의 늦은 기록이면 nil.
    /// 새로 만들거나 다시 살렸으면 `session.start`를 남긴다(SessionStart가 아니어도 — 훅을 세션 중간에 등록한 경우).
    func mainSession(_ input: HookInput, at date: Date, create: Bool) -> Session? {
        if let session = fetchSession(input.sessionID) {
            guard let endedAt = session.endedAt else { return session }
            guard create, date > endedAt else { return nil }
            session.endedAt = nil
            session.cachedState = .live
            recordStart(session, input, at: date)
            return session
        }
        guard create, let project = matchProject(input.cwd) else { return nil }
        let session = Session(
            id: input.sessionID, kind: .main, cwd: input.cwd,
            gitBranch: gitBranch(input.cwd), startedAt: date
        )
        context.insert(session)
        session.project = project
        recordStart(session, input, at: date)
        return session
    }

    private func recordStart(_ session: Session, _ input: HookInput, at date: Date) {
        Event.record(.sessionStart, in: context, project: session.project, session: session, at: date,
                     payload: input.source.map { ["source": .string($0)] } ?? [:])
    }

    /// 활동 시각을 앞으로만 옮기고 캐시 상태를 live로.
    func touch(_ session: Session, at date: Date) {
        if date > session.lastSeenAt { session.lastSeenAt = date }
        if session.endedAt == nil { session.cachedState = .live }
    }

    /// 세션을 끝낸다: 열린 연결을 모두 닫고 `session.end` 기록.
    func end(_ session: Session, at date: Date, reason: String? = nil) {
        guard session.endedAt == nil else { return }
        touch(session, at: date)
        CardLifecycle.detachAll(session, at: date, in: context)
        Event.record(.sessionEnd, in: context, project: session.project, session: session, at: date,
                     payload: reason.map { ["reason": .string($0)] } ?? [:])
    }
}
