import Foundation
import SwiftData

/// `project_status`(TRK-63)·`work_file`(TRK-62). SPEC 7장.
extension MCPTools {

    /// `text`를 주면 프로젝트 지금 상황을 새로 쓰고, 안 주면 최신 상황을 읽는다.
    func projectStatus(_ args: JSONValue) throws -> JSONValue {
        let project = try resolveProject(args)
        guard let raw = optionalString(args, "text") else {
            return ["project": .string(project.key), "status": ProjectStatus.latest(for: project).map(statusJSON) ?? .null]
        }
        let text = try ProjectStatus.normalized(raw)
        let session = optionalString(args, "sessionId").flatMap(fetchSession)
        let provider = try session?.provider ?? provider(args)
        var payload: [String: EventValue] = ["summary": .string(text), "provider": .string(provider.rawValue)]
        if let session { payload["sessionId"] = .string(session.id) }
        let date = now()
        Event.record(.projectStatus, in: context, project: project, session: session, at: date, payload: payload)
        return ["project": .string(project.key), "status": statusJSON(
            ProjectStatus.Entry(text: text, at: date, provider: provider, sessionID: session?.id))]
    }

    /// 정리 안 된 작업 하나를 처리한다. `cardId`를 주면 그 세션의 파일 변경·커밋·검증 기록을 카드에 잇고, 안 주면 넘긴다.
    /// 카드 상태·연결(`CardSession`)은 바꾸지 않는다(작업중 판정과 무관).
    func workFile(_ args: JSONValue) throws -> JSONValue {
        let session = try findEndedSession(try requiredString(args, "sessionId"))
        guard let project = session.project else { throw MCPToolError("프로젝트가 없는 세션") }
        guard !UnfiledWork.everAttached(session) else { throw MCPToolError("카드에 연결된 적 있는 세션: 정리할 것 없음") }
        guard !UnfiledWork.filedSessionIDs(for: project).contains(session.id) else {
            throw MCPToolError("이미 정리한 세션: \(UnfiledWork.shortID(session))")
        }
        let date = now()
        guard let cardID = optionalString(args, "cardId") else {
            Event.record(.sessionFiled, in: context, project: project, session: session, at: date,
                         payload: ["sessionId": .string(session.id), "outcome": .string("dismissed")])
            return ["sessionId": .string(session.id), "outcome": "dismissed"]
        }
        let card = try findCard(cardID)
        guard card.project === project else { throw MCPToolError("세션과 카드의 프로젝트가 다름") }
        guard card.status != .archived else { throw MCPToolError("보관된 카드") }

        let types: Set<EventType> = [.fileChanged, .commit, .check]
        let moved = ([session] + (session.children ?? [])).flatMap { $0.events ?? [] }
            .filter { types.contains($0.type) && $0.card == nil && $0.project === project }
        for event in moved { event.card = card }
        let files = Set(moved.filter { $0.type == .fileChanged }.compactMap { $0.payloadValues["path"]?.stringValue }).count
        Event.record(.sessionFiled, in: context, project: project, card: card, session: session, at: date,
                     payload: ["sessionId": .string(session.id), "outcome": .string("filed"),
                               "cardId": .string(card.displayID), "files": .int(files), "moved": .int(moved.count)])
        return ["sessionId": .string(session.id), "outcome": "filed", "cardId": .string(card.displayID),
                "files": JSONValue(files), "moved": JSONValue(moved.count)]
    }

    /// 끝난 메인 세션을 전체 ID나 블록의 짧은 ID(앞부분 8자 이상, 하나만 맞아야 함)로 찾는다.
    func findEndedSession(_ raw: String) throws -> Session {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var session = fetchSession(id)
        if session == nil, id.count >= 8 {
            let main = SessionKind.main.rawValue
            let found = (try? context.fetch(FetchDescriptor<Session>(
                predicate: #Predicate<Session> { $0.kindRaw == main && $0.id.starts(with: id) }))) ?? []
            guard found.count <= 1 else { throw MCPToolError("짧은 ID가 여러 세션과 맞음: \(id). 더 길게 보낸다") }
            session = found.first
        }
        guard let session, session.kind == .main else { throw MCPToolError("세션 없음: \(id)") }
        guard session.endedAt != nil else { throw MCPToolError("끝나지 않은 세션: 지금 세션이면 card_start로 연결한다") }
        return session
    }

    func statusJSON(_ entry: ProjectStatus.Entry) -> JSONValue {
        var json: [String: JSONValue] = ["text": .string(entry.text), "at": JSONValue(entry.at),
                                         "stale": .bool(entry.isStale(now: now()))]
        if let provider = entry.provider { json["provider"] = .string(provider.rawValue) }
        if let id = entry.sessionID { json["sessionId"] = .string(id) }
        return .object(json)
    }
}
