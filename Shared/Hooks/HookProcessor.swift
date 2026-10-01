import Foundation
import SwiftData

/// 훅 한 건을 기록으로 바꾼다(SPEC 5장). 서버와 outbox 흡수가 같은 것을 쓴다.
/// 넘겨받은 context가 속한 액터(앱에서는 메인 액터)에서만 부른다. Sendable이 아니다.
public final class HookProcessor {
    public let context: ModelContext
    /// 최근 처리의 저장 실패. 진단 화면은 오류 원문이나 사용자 입력을 노출하지 않는다.
    public private(set) var lastSaveFailed = false
    /// 최근 처리에서 대기로 둔 블록의 응답 ID(`X-Waypoint-Context-ID`). 블록을 주지 않았거나 확인 없는 스크립트면 nil.
    public internal(set) var lastContextID: String?
    /// 서버 큐가 받아 둔 블록 수신 확인. 다음 훅 처리 때 그 세션의 대기 블록을 확정한다(`applyAcknowledgement`).
    public let contextAcks: ContextAckInbox
    public var stallTimeout: TimeInterval
    /// 프로젝트 매칭에 쓰는 홈 폴더(`~` 펼치기). 테스트에서 바꾼다.
    public var home: String
    /// cwd → git 브랜치. 테스트에서 바꾼다.
    public var gitBranch: (String) -> String?
    /// 저장. 테스트에서 실패를 흉내 낸다.
    var saveContext: (ModelContext) throws -> Void = { try $0.save() }

    /// `PreToolUse(Agent)`에서 올려 두고 `SubagentStart`에서 꺼내는 대기 항목. 메모리에만 둔다.
    struct PendingSpawn {
        let agentType: String?
        let cardNumber: Int?
        let at: Date
    }
    /// 부모 세션 ID → 먼저 올린 순
    var pendingSpawns: [String: [PendingSpawn]] = [:]
    /// 대기 목록에 이미 올린 서브에이전트 도구 호출(`부모 세션|tool_use_id` → 시각). 같은 훅을 다시 받아도 두 번 올리지 않는다.
    var seenSpawns: [String: Date] = [:]
    /// 같은 훅의 재수신으로 보는 시간 폭(10분). 실시간 응답이 늦어 outbox에도 쓰인 줄은 원래 시각 근처로 들어온다.
    public static let redeliveryWindow: TimeInterval = 10 * 60
    /// ID 없는 옛 outbox 줄의 요청 문장을 같은 요청으로 보는 시간 폭(10초).
    public static let promptRedeliveryTolerance: TimeInterval = 10
    /// 대기 항목이 짝을 기다리는 시간(10분). 넘으면 버린다.
    public static let pendingLifetime: TimeInterval = 10 * 60
    /// `subagent_type`을 안 준 Agent 호출의 기본 에이전트 종류(문서 기준).
    public static let defaultAgentType = "general-purpose"

    public init(
        context: ModelContext,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout,
        home: String = NSHomeDirectory(),
        gitBranch: @escaping (String) -> String? = { GitInfo.branch(at: $0) },
        contextAcks: ContextAckInbox = ContextAckInbox()
    ) {
        self.context = context
        self.contextAcks = contextAcks
        self.stallTimeout = stallTimeout
        self.home = home
        self.gitBranch = gitBranch
    }

    /// 훅 본문(JSON)을 처리하고 저장한다. 대화에 주입할 텍스트가 있으면 그것을, 아니면 nil.
    /// 주입 텍스트: `SessionStart`는 늘(빈 문자열일 수 있다), `UserPromptSubmit`은 블록을 받지 못한 세션에(`lateContext`).
    /// 읽을 수 없는 본문은 무시한다(nil). `claudePid`는 훅을 부른 Claude Code 프로세스(머리·outbox 필드).
    /// `delivers`가 false면(outbox 흡수 — 이미 지난 훅) 텍스트를 만들지 않고 블록을 줬다고 적지도 않는다.
    /// `acknowledges`면 스크립트가 출력 뒤 확인(`POST /hooks/ack`)을 보낸다: 블록을 대기로 두고 `lastContextID`를 준다.
    /// 아니면(옛 스크립트) 블록을 주는 즉시 받은 것으로 적는다(TRK-35).
    @discardableResult
    public func handle(event: String?, json: Data, at date: Date, claudePid: Int? = nil,
                       delivers: Bool = true, provider: AgentProvider = .claude, processPid: Int? = nil,
                       acknowledges: Bool = false) -> String? {
        lastSaveFailed = false
        lastContextID = nil
        guard var input = HookInput(event: event, json: json, provider: provider) else { return nil }
        input.claudePid = provider == .claude ? claudePid : nil
        input.processPid = processPid
        return handle(input, at: date, delivers: delivers, acknowledges: acknowledges)
    }

    @discardableResult
    public func handle(_ input: HookInput, at date: Date, delivers: Bool = true, acknowledges: Bool = false) -> String? {
        lastSaveFailed = false
        lastContextID = nil
        // 저장에 실패하면 DB와 함께 메모리의 대기 항목도 되돌린다. 같은 훅을 다시 처리해도 대기 항목이 겹치거나 사라지지 않게.
        // rollback이 되돌리지 못한 메모리 값은 저장소 값으로 다시 읽는다(`ContextReload`). 그대로 두면 다음 저장에 섞인다.
        let spawns = pendingSpawns
        let seen = seenSpawns
        // 받아 둔 확인을 늦은 주입 판단 전에 반영한다.
        let acknowledged = applyAcknowledgement(input)
        let result = process(input, at: date, delivers: delivers, acknowledges: acknowledges)
        if let main = fetchSession(input.sessionID), main.project?.archivedAt == nil {
            let target = input.event == "SubagentStart" ? subagentSession(input) : (subagentSession(input) ?? main)
            SessionActivityRules.observe(input, session: target ?? main, at: date)
        }
        do {
            try saveContext(context)
        } catch {
            lastSaveFailed = true
            // 대기로 적지 못한 블록의 ID는 돌려주지 않는다(확인이 와도 찾을 곳이 없다).
            lastContextID = nil
            // 저장하지 못한 확정은 확인을 되돌려 다음 훅에서 다시 쓴다.
            if let acknowledged { contextAcks.insert(acknowledged) }
            context.rollback()
            ContextReload.apply(context)
            pendingSpawns = spawns
            seenSpawns = seen
        }
        return result
    }

    func process(_ input: HookInput, at date: Date, delivers: Bool = true, acknowledges: Bool = false) -> String? {
        switch input.event {
        case "SessionStart":
            let text = sessionStart(input, at: date, delivers: delivers, acknowledges: acknowledges)
            return delivers ? text : nil
        case "UserPromptSubmit":
            userPromptSubmit(input, at: date)
            return delivers ? lateContext(input, at: date, acknowledges: acknowledges) : nil
        case "Stop", "Interrupt", "PermissionRequest":
            heartbeat(input, at: date)
        case "PostToolUseFailure":
            postToolUseFailure(input, at: date)
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

    /// 이 훅의 폴더(또는 이미 있는 세션)가 보관된 프로젝트에 속하는지.
    func isArchivedFolder(_ input: HookInput) -> Bool {
        if let project = fetchSession(input.sessionID)?.project { return project.archivedAt != nil }
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return ProjectMatcher.nearest(for: input.cwd, in: projects, home: home)?.archivedAt != nil
    }

    /// 메인 세션. 없으면 `create`일 때 cwd로 프로젝트를 찾아 만든다(등록 안 된 폴더면 nil).
    /// 끝난 세션은 그 뒤 시각의 훅이 오면(`create`일 때) 다시 살린다. 끝난 시각 이전의 늦은 기록이면 nil.
    /// 새로 만들거나 다시 살렸으면 `session.start`를 남긴다(SessionStart가 아니어도 — 훅을 세션 중간에 등록한 경우).
    /// 훅에 Claude Code PID가 있으면 세션에 적는다(`recordPid`).
    /// 보관된 프로젝트의 세션은 없는 것처럼 본다(훅을 기록하지 않는다).
    func mainSession(_ input: HookInput, at date: Date, create: Bool) -> Session? {
        if let session = fetchSession(input.sessionID) {
            guard session.project?.archivedAt == nil else { return nil }
            guard let endedAt = session.endedAt else {
                recordPid(session, input, at: date)
                return session
            }
            guard create, date > endedAt else { return nil }
            session.endedAt = nil
            session.cachedState = .live
            SessionActivityRules.reset(session)
            // 새 훅에 PID가 없으면 이전 프로세스를 계속 검사하지 않는다.
            session.claudePid = nil
            session.processPid = nil
            recordPid(session, input, at: date)
            recordStart(session, input, at: date)
            return session
        }
        guard create, let project = matchProject(input.cwd) else { return nil }
        let session = Session(
            id: input.sessionID, kind: .main, cwd: input.cwd,
            gitBranch: gitBranch(input.cwd), startedAt: date, provider: input.provider
        )
        context.insert(session)
        session.project = project
        recordPid(session, input, at: date)
        recordStart(session, input, at: date)
        return session
    }

    /// 메인 세션의 Claude Code PID를 적는다. 비어 있거나, 이 훅이 지금까지 받은 것 중 가장 새것이면 바꾼다
    /// (`--resume`은 같은 `session_id`를 새 프로세스로 이어 간다). outbox로 늦게 들어온 옛 훅은 PID를 되돌리지 않는다.
    /// `touch` 전에 불러야 한다(`lastSeenAt`과 비교).
    private func recordPid(_ session: Session, _ input: HookInput, at date: Date) {
        let pid = input.provider == .claude ? input.claudePid : input.processPid
        guard let pid else { return }
        if input.provider == .claude {
            if session.claudePid == nil || date >= session.lastSeenAt { session.claudePid = pid }
        } else if session.processPid == nil || date >= session.lastSeenAt {
            session.processPid = pid
        }
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

    /// 메인 세션을 끝낸다: 끝나지 않은 하위 세션부터 닫고, 세션의 열린 연결을 모두 닫고 `session.end`(`reason`)를 남긴다.
    /// `SessionEnd` 훅과 `SessionEnd`가 오지 않은 세션 정리(`sweep`)가 같이 쓴다. 이미 끝났으면 아무것도 안 한다.
    /// `activity`가 false면 `lastSeenAt`을 옮기지 않는다(훅 없이 앱이 끝낸 경우 — 마지막 활동은 그대로).
    /// 저장(save)은 호출 쪽에서 한다.
    public func finish(_ session: Session, at date: Date, reason: String?, activity: Bool = true) {
        guard session.endedAt == nil else { return }
        for child in session.children ?? [] where child.endedAt == nil {
            end(child, at: date, reason: reason, activity: activity)
        }
        end(session, at: date, reason: reason, activity: activity)
        pendingSpawns[session.id] = nil
        seenSpawns = seenSpawns.filter { !$0.key.hasPrefix(session.id + "|") }
    }

    /// 세션을 끝낸다: 열린 연결을 모두 닫고 `session.end` 기록.
    func end(_ session: Session, at date: Date, reason: String? = nil, activity: Bool = true) {
        guard session.endedAt == nil else { return }
        if activity { touch(session, at: date) }
        CardLifecycle.detachAll(session, at: date, in: context, reason: reason)
        session.pendingToolsData = nil
        session.endReason = reason
        Event.record(.sessionEnd, in: context, project: session.project, session: session, at: date,
                     payload: reason.map { ["reason": .string($0)] } ?? [:])
    }
}
