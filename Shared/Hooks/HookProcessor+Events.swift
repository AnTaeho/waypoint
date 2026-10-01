import Foundation
import SwiftData

/// 이벤트별 처리. 표는 SPEC 5장.
extension HookProcessor {

    /// 등록 안 된 폴더는 안내 한 줄, 보관된 프로젝트 폴더는 빈 본문(아무것도 주입하지 않는다).
    /// 블록을 실제로 건넬 때(`delivers`)만 세션에 블록을 준 것을 적는다(`offerContext`).
    func sessionStart(_ input: HookInput, at date: Date, delivers: Bool, acknowledges: Bool = false) -> String {
        guard let session = mainSession(input, at: date, create: true), let project = session.project
        else { return isArchivedFolder(input) ? "" : SessionContext.awaitingProject(input) }
        touch(session, at: date)
        if delivers { offerContext(project, to: session, restart: true, acknowledges: acknowledges) }
        return SessionContext.text(project: project, session: session, now: date, stallTimeout: stallTimeout)
    }

    /// UserPromptSubmit: heartbeat에 더해 메인 세션의 마지막 요청 문장(`lastPrompt`)과 그 시각(`lastPromptAt`)을 적는다.
    /// outbox로 늦게 들어온 옛 프롬프트는 더 최근 값을 덮지 않는다: 비어 있거나 이 훅이 지금까지 받은 것 중
    /// 가장 새것(`at >= lastSeenAt`, `touch` 전에 비교)일 때만 바꾼다.
    func userPromptSubmit(_ input: HookInput, at date: Date) {
        guard let session = mainSession(input, at: date, create: true) else { return }
        if let prompt = HookParsing.userPrompt(input) {
            let duplicate = isRedeliveredPrompt(input, text: prompt, in: session, at: date)
            if !duplicate {
                let ownership = (session.events ?? []).filter {
                    $0.at <= date && ($0.type == .sessionStart || $0.payloadValues["kind"]?.stringValue == "project.bound")
                }.max { $0.at < $1.at }
                let project = ownership?.project ?? matchProject(input.cwd) ?? session.project
                let cards = (session.cardSessions ?? []).filter {
                    $0.attachedAt <= date && ($0.detachedAt.map { $0 > date } ?? true)
                        && $0.card?.project?.id == project?.id
                }.compactMap(\.card)
                var payload: [String: EventValue] = ["kind": .string("user.prompt"), "text": .string(prompt)]
                if let id = input.promptID { payload["promptId"] = .string(id) }
                Event.record(.note, in: context, project: project, card: cards.count == 1 ? cards.first : nil,
                             session: session, at: date, payload: payload)
            }
        }
        if let prompt = HookParsing.userPrompt(input), session.lastPrompt == nil || date >= session.lastSeenAt {
            session.lastPrompt = prompt
            session.lastPromptAt = date
        }
        touch(session, at: date)
        if let sub = subagentSession(input) { touch(sub, at: date) }
    }

    /// Stop: 활동 시각만. 서브에이전트 안이면 그 하위 세션도.
    func heartbeat(_ input: HookInput, at date: Date) {
        guard let session = mainSession(input, at: date, create: true) else { return }
        touch(session, at: date)
        if let sub = subagentSession(input) { touch(sub, at: date) }
    }

    /// 서브에이전트 도구 호출이면 카드 ID·에이전트 종류를 대기 목록에 올린다.
    func preToolUse(_ input: HookInput, at date: Date) {
        guard let session = mainSession(input, at: date, create: true) else { return }
        touch(session, at: date)
        let sub = subagentSession(input)
        if let sub { touch(sub, at: date) }
        guard let tool = input.toolName,
              HookParsing.subagentTools.contains(tool) || input.provider == .codex && tool == "spawn_agent"
        else { return }

        let prompt = input.toolInput["prompt"] as? String ?? input.toolInput["message"] as? String ?? ""
        let key = session.project?.key
        let number = HookParsing.cardReferences(in: prompt).first(where: { $0.key == key })?.number
        let agentType = (input.toolInput["subagent_type"] as? String ?? input.toolInput["agent_type"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let defaultType = input.provider == .codex ? "default" : Self.defaultAgentType
        let parentID = session.id
        if let id = input.toolUseID {
            // 같은 도구 호출을 다시 받았다(실시간 두 번, 실시간 + outbox). 두 번 올리면 다음 서브에이전트가 이 카드와 짝지어진다.
            seenSpawns = seenSpawns.filter { abs(date.timeIntervalSince($0.value)) <= Self.pendingLifetime }
            guard seenSpawns.updateValue(date, forKey: parentID + "|" + id) == nil else { return }
        }
        var queue = livePending(for: parentID, at: date)
        queue.append(PendingSpawn(agentType: agentType ?? defaultType, cardNumber: number, at: date))
        pendingSpawns[parentID] = queue
    }

    /// 하위 세션을 만들고(`id`=agent_id), 대기 목록에서 짝을 찾아 카드가 있으면 연결한다.
    func subagentStart(_ input: HookInput, at date: Date) {
        guard let agentID = input.agentID,
              let parent = mainSession(input, at: date, create: true)
        else { return }
        touch(parent, at: date)

        let sub: Session
        if let existing = fetchSession(agentID) {
            // 다시 이어 붙은 서브에이전트
            guard existing.kind == .subagent else { return }
            sub = existing
            if existing.endedAt != nil {
                existing.endedAt = nil
                existing.cachedState = .live
            }
        } else {
            let name = (input.agentType ?? "").isEmpty ? nil : input.agentType
            sub = Session(id: agentID, kind: .subagent, agentName: name, cwd: input.cwd,
                          gitBranch: parent.gitBranch, startedAt: date, provider: input.provider)
            context.insert(sub)
            sub.project = parent.project
            sub.parent = parent
            Event.record(.sessionStart, in: context, project: parent.project, session: sub, at: date,
                         payload: name.map { ["agentName": .string($0)] } ?? [:])
        }
        touch(sub, at: date)

        let agentType = input.agentType ?? (input.provider == .codex ? "default" : nil)
        guard let spawn = takePending(for: parent.id, agentType: agentType, at: date),
              let number = spawn.cardNumber,
              let card = parent.project?.cards?.first(where: { $0.number == number && $0.status != .archived })
        else { return }
        CardLifecycle.attach(card, sub, at: date, in: context)
    }

    /// 파일 변경·커밋을 지금 작업중 카드에 남긴다. 서브에이전트가 카드 없이 일하면 부모 세션의 카드로.
    func postToolUse(_ input: HookInput, at date: Date) {
        let files = HookParsing.changedFiles(input)
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let matches = files.compactMap { ProjectMatcher.project(for: $0.path, in: projects, home: home) }
        var main = mainSession(input, at: date, create: true)
        // 시작 폴더가 미등록이어도 실제 변경 파일이 한 프로젝트에 속하면 세션을 만들 수 있다.
        let workdir = input.toolInput["workdir"] as? String ?? input.toolInput["cwd"] as? String
        let workingProject = workdir.flatMap { $0.hasPrefix("/") ? ProjectMatcher.project(for: $0, in: projects, home: home) : nil }
        let keys = Set(matches.map(\.id))
        // 이미 있는 세션(끝난 뒤 늦게 온 기록 포함)을 같은 ID로 또 만들지 않는다.
        if main == nil, fetchSession(input.sessionID) == nil,
           !matches.isEmpty || workingProject != nil, !isArchivedFolder(input) {
            let created = Session(id: input.sessionID, cwd: input.cwd, startedAt: date, provider: input.provider)
            context.insert(created)
            created.claudePid = input.claudePid
            created.processPid = input.processPid
            let project = keys.count == 1 ? matches.first : (keys.isEmpty ? workingProject : nil)
            if let project { SessionProjectBinding.bind(created, to: project, at: date, in: context) }
            Event.record(.sessionStart, in: context, project: project, session: created, at: date)
            main = created
        }
        guard let main else { return }
        touch(main, at: date)
        let sub = subagentSession(input)
        if let sub { touch(sub, at: date) }
        let acting = sub ?? main
        var cards = acting.openCardSessions.compactMap(\.card)
        if cards.isEmpty, sub != nil { cards = main.openCardSessions.compactMap(\.card) }
        let commitProject = toolProject(input, acting: acting, projects: projects)
        // 같은 도구 호출의 재수신이면 파일·커밋은 이미 남았다(검증 근거는 `recordCheck`가 따로 거른다).
        guard !isRedeliveredTool(input, in: acting, at: date) else {
            recordCheck(input, at: date, acting: acting, cards: cards, project: commitProject)
            return
        }
        var tool: [String: EventValue] = [:]
        if let id = input.toolUseID { tool["toolUseId"] = .string(id) }

        for file in files {
            // 다른 등록 프로젝트를 수정했으면 파일 자체의 소속을 우선한다.
            let nearest = ProjectMatcher.nearest(for: file.path, in: projects, home: home)
            if nearest?.archivedAt != nil { continue }
            // 등록 밖 절대 경로를 현재 프로젝트 기록에 섞지 않는다.
            guard let project = nearest ?? (file.path.hasPrefix("/") ? nil : acting.project) else { continue }
            let targets = unique(cards.filter { $0.project === project })
            let path = ProjectMatcher.relativePath(file.path, in: project, home: home)
            for card in targets.isEmpty ? [Card?.none] : targets.map(Optional.some) {
                Event.record(.fileChanged, in: context, project: project, card: card, session: acting, at: date,
                             payload: tool.merging(["path": .string(path), "added": .int(file.added),
                                                    "removed": .int(file.removed)]) { $1 })
            }
        }
        if let commit = HookParsing.commit(input), let project = commitProject {
            if let branch = commit.branch { acting.gitBranch = branch }
            let targets = unique(cards.filter { $0.project === project })
            for card in targets.isEmpty ? [Card?.none] : targets.map(Optional.some) {
                Event.record(.commit, in: context, project: project, card: card, session: acting, at: date,
                             payload: tool.merging(["hash": .string(commit.hash),
                                                    "message": .string(commit.message)]) { $1 })
            }
        }
        recordCheck(input, at: date, acting: acting, cards: cards, project: commitProject)
    }

    /// PostToolUseFailure: 활동 시각에 더해, 실패한 검증 명령을 근거로 남긴다.
    func postToolUseFailure(_ input: HookInput, at date: Date) {
        guard let main = mainSession(input, at: date, create: true) else { return }
        touch(main, at: date)
        let sub = subagentSession(input)
        if let sub { touch(sub, at: date) }
        let acting = sub ?? main
        var cards = acting.openCardSessions.compactMap(\.card)
        if cards.isEmpty, sub != nil { cards = main.openCardSessions.compactMap(\.card) }
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        recordCheck(input, at: date, acting: acting, cards: cards,
                    project: toolProject(input, acting: acting, projects: projects))
    }

    /// 검증 명령 실행을 그 세션의 열린 카드(서브에이전트가 카드 없이 일하면 부모의 카드)에 근거로 남긴다.
    /// 카드가 없으면 남기지 않는다(조건과 이을 곳이 없다). 같은 도구 호출은 한 번만.
    func recordCheck(_ input: HookInput, at date: Date, acting: Session, cards: [Card], project: Project?) {
        guard let check = HookParsing.check(input), let project else { return }
        let record = CheckRecord(at: date, command: check.command, outcome: check.outcome, source: .hook,
                                 exitCode: check.exitCode, provider: input.provider)
        for card in unique(cards.filter { $0.project === project }) {
            if let id = input.toolUseID, CardEvidence.hasRecord(card: card, toolUseID: id) { continue }
            CardEvidence.record(record, card: card, session: acting, toolUseID: input.toolUseID, in: context)
        }
    }

    /// 하위 세션 종료. 모르는 agent_id(앱 내부 에이전트 등)는 무시한다.
    func subagentStop(_ input: HookInput, at date: Date) {
        guard let sub = subagentSession(input) else { return }
        if let main = mainSession(input, at: date, create: false) { touch(main, at: date) }
        end(sub, at: date)
    }

    /// 세션 종료: 끝나지 않은 하위 세션부터 닫고 세션을 닫는다.
    func sessionEnd(_ input: HookInput, at date: Date) {
        guard let session = fetchSession(input.sessionID) else { return }
        finish(session, at: date, reason: input.reason)
    }

    // MARK: - 도우미

    /// 명령(커밋·검증)이 실행된 프로젝트. 도구 입력의 `workdir`/`cwd`가 있으면 그 폴더, 없으면 훅의 `cwd`
    /// (Claude가 `cd`하면 따라 바뀐다 — hooks 문서 「cwd follows Claude」). 훅 `cwd`가 등록 밖이면 세션의 프로젝트
    /// (미등록 상위 폴더에서 시작해 `session_bind`한 경우). 보관된 프로젝트 폴더면 nil.
    func toolProject(_ input: HookInput, acting: Session, projects: [Project]) -> Project? {
        if let workdir = input.toolInput["workdir"] as? String ?? input.toolInput["cwd"] as? String {
            return workdir.hasPrefix("/") ? ProjectMatcher.project(for: workdir, in: projects, home: home) : nil
        }
        guard let here = ProjectMatcher.nearest(for: input.cwd, in: projects, home: home) else { return acting.project }
        return here.archivedAt == nil ? here : nil
    }

    /// 같은 도구 호출(`tool_use_id`)의 파일·커밋 기록이 이 세션에 이미 있는지. ID가 없으면 거르지 않는다.
    func isRedeliveredTool(_ input: HookInput, in session: Session, at date: Date) -> Bool {
        guard let id = input.toolUseID else { return false }
        return (session.events ?? []).contains { event in
            (event.typeRaw == EventType.fileChanged.rawValue || event.typeRaw == EventType.commit.rawValue)
                && abs(event.at.timeIntervalSince(date)) <= Self.redeliveryWindow
                && event.payloadValues["toolUseId"]?.stringValue == id
        }
    }

    /// 같은 요청을 다시 받았는지. 둘 다 요청 ID가 있으면 ID로, 아니면(옛 outbox 줄) 같은 문장이 10초 안에 있으면.
    func isRedeliveredPrompt(_ input: HookInput, text: String, in session: Session, at date: Date) -> Bool {
        (session.events ?? []).contains { event in
            guard event.typeRaw == EventType.note.rawValue else { return false }
            let gap = abs(event.at.timeIntervalSince(date))
            guard gap <= Self.redeliveryWindow else { return false }
            let values = event.payloadValues
            guard values["kind"]?.stringValue == "user.prompt" else { return false }
            if let id = input.promptID, let stored = values["promptId"]?.stringValue { return id == stored }
            return gap <= Self.promptRedeliveryTolerance && values["text"]?.stringValue == text
        }
    }

    /// 훅이 서브에이전트 안에서 났으면 그 하위 세션(이미 만들어진 것만).
    func subagentSession(_ input: HookInput) -> Session? {
        guard let agentID = input.agentID, let session = fetchSession(agentID), session.kind == .subagent
        else { return nil }
        return session
    }

    func livePending(for parentID: String, at date: Date) -> [PendingSpawn] {
        (pendingSpawns[parentID] ?? []).filter { date.timeIntervalSince($0.at) <= Self.pendingLifetime }
    }

    /// 같은 에이전트 종류 중 가장 먼저 올린 것을 꺼낸다. 없으면 nil(다른 종류와 짝짓지 않는다).
    func takePending(for parentID: String, agentType: String?, at date: Date) -> PendingSpawn? {
        var queue = livePending(for: parentID, at: date)
        let wanted = (agentType ?? "").isEmpty ? Self.defaultAgentType : agentType
        guard let index = queue.firstIndex(where: { $0.agentType == wanted }) else {
            pendingSpawns[parentID] = queue
            return nil
        }
        let spawn = queue.remove(at: index)
        pendingSpawns[parentID] = queue
        return spawn
    }

    func unique(_ cards: [Card]) -> [Card] {
        var seen = Set<ObjectIdentifier>()
        return cards.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
