import Foundation
import SwiftData

/// 이벤트별 처리. 표는 SPEC 5장.
extension HookProcessor {

    func sessionStart(_ input: HookInput, at date: Date) -> String {
        guard let session = mainSession(input, at: date, create: true), let project = session.project
        else { return SessionContext.unregistered }
        touch(session, at: date)
        return SessionContext.text(project: project, session: session, now: date, stallTimeout: stallTimeout)
    }

    /// UserPromptSubmit·Stop: 활동 시각만. 서브에이전트 안이면 그 하위 세션도.
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
        guard let tool = input.toolName, HookParsing.subagentTools.contains(tool) else { return }

        let prompt = input.toolInput["prompt"] as? String ?? ""
        let key = session.project?.key
        let number = HookParsing.cardReferences(in: prompt).first { $0.key == key }?.number
        let agentType = (input.toolInput["subagent_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let parentID = session.id
        var queue = livePending(for: parentID, at: date)
        queue.append(PendingSpawn(agentType: agentType ?? Self.defaultAgentType, cardNumber: number, at: date))
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
                          gitBranch: parent.gitBranch, startedAt: date)
            context.insert(sub)
            sub.project = parent.project
            sub.parent = parent
            Event.record(.sessionStart, in: context, project: parent.project, session: sub, at: date,
                         payload: name.map { ["agentName": .string($0)] } ?? [:])
        }
        touch(sub, at: date)

        guard let spawn = takePending(for: parent.id, agentType: input.agentType, at: date),
              let number = spawn.cardNumber,
              let card = parent.project?.cards?.first(where: { $0.number == number && $0.status != .archived })
        else { return }
        CardLifecycle.attach(card, sub, at: date, in: context)
    }

    /// 파일 변경·커밋을 지금 작업중 카드에 남긴다. 서브에이전트가 카드 없이 일하면 부모 세션의 카드로.
    func postToolUse(_ input: HookInput, at date: Date) {
        guard let main = mainSession(input, at: date, create: true), let project = main.project else { return }
        touch(main, at: date)
        let sub = subagentSession(input)
        if let sub { touch(sub, at: date) }
        let acting = sub ?? main
        var cards = acting.openCardSessions.compactMap(\.card)
        if cards.isEmpty, sub != nil { cards = main.openCardSessions.compactMap(\.card) }
        let targets: [Card?] = cards.isEmpty ? [nil] : unique(cards).map { $0 }

        for file in HookParsing.changedFiles(input) {
            let path = ProjectMatcher.relativePath(file.path, in: project, home: home)
            for card in targets {
                Event.record(.fileChanged, in: context, project: project, card: card, session: acting, at: date,
                             payload: ["path": .string(path), "added": .int(file.added), "removed": .int(file.removed)])
            }
        }
        if let commit = HookParsing.commit(input) {
            if let branch = commit.branch { main.gitBranch = branch }
            for card in targets {
                Event.record(.commit, in: context, project: project, card: card, session: acting, at: date,
                             payload: ["hash": .string(commit.hash), "message": .string(commit.message)])
            }
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
        guard let session = fetchSession(input.sessionID), session.endedAt == nil else { return }
        for child in session.children ?? [] where child.endedAt == nil {
            end(child, at: date)
        }
        end(session, at: date, reason: input.reason)
        pendingSpawns[session.id] = nil
    }

    // MARK: - 도우미

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
