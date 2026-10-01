import Foundation
import SwiftData

extension MCPTools {
    /// 훅 또는 실행 환경에서 받은 실제 세션 ID를 작업 대상 프로젝트에 연결한다.
    func sessionBind(_ args: JSONValue) throws -> JSONValue {
        let project = try resolveProject(args)
        let id = try requiredString(args, "sessionId").trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = try provider(args)
        let cwd = try requiredString(args, "cwd")
        guard !id.isEmpty, cwd.hasPrefix("/") else { throw MCPToolError("실제 sessionId와 시작 폴더 절대 경로가 필요함") }
        guard (provider == .codex) == id.hasPrefix("codex:"), id != "codex:" else {
            throw MCPToolError("Codex sessionId는 codex: 접두사를 포함해야 함")
        }
        let date = now()
        let session: Session
        if let existing = fetchSession(id) {
            guard existing.provider == provider, existing.kind == .main, SessionSweep.canReconnect(existing) else {
                throw MCPToolError("같은 도구의 메인 세션만 연결할 수 있음. 명시적으로 종료된 세션은 시작 훅으로 재개해야 함")
            }
            session = existing
            if session.endedAt != nil {
                session.endedAt = nil
                session.cachedState = .live
                SessionActivityRules.reset(session)
                session.claudePid = nil
                session.processPid = nil
                session.confirmContext(nil)
                Event.record(.sessionStart, in: context, project: project, session: session, at: date,
                             payload: ["source": .string("tracking-reconnect")])
            }
        } else {
            session = Session(id: id, cwd: cwd, startedAt: date, provider: provider)
            context.insert(session)
            Event.record(.sessionStart, in: context, project: project, session: session, at: date,
                         payload: ["source": .string("explicit-project")])
        }
        let detached = SessionProjectBinding.bind(session, to: project, at: date, in: context)
        if date > session.lastSeenAt { session.lastSeenAt = date }
        session.confirmContext(project.key)
        return ["project": projectJSON(project), "sessionId": .string(session.id),
                "provider": .string(provider.rawValue), "detached": .array(detached.map { .string($0) }),
                "context": .string(SessionContext.text(project: project, session: session, now: date))]
    }
}
