import Foundation
import SwiftData

/// 입력 읽기, 조회, 결과 JSON.
extension MCPTools {

    // MARK: - 입력

    func requiredString(_ args: JSONValue, _ key: String) throws -> String {
        guard let value = args[key]?.stringValue else { throw MCPToolError("\(key)(문자열)가 필요함") }
        return value
    }

    func optionalString(_ args: JSONValue, _ key: String) -> String? {
        args[key]?.stringValue
    }

    func provider(_ args: JSONValue) throws -> AgentProvider {
        if let raw = optionalString(args, "provider") {
            guard let provider = AgentProvider(rawValue: raw) else {
                throw MCPToolError("provider는 claude·codex 중 하나")
            }
            return provider
        }
        return .claude
    }

    func optionalStatus(_ args: JSONValue, _ key: String) throws -> CardStatus? {
        guard let raw = optionalString(args, key) else { return nil }
        guard let status = CardStatus(rawValue: raw) else {
            throw MCPToolError("\(key)는 \(CardStatus.allCases.map(\.rawValue).joined(separator: "·")) 중 하나")
        }
        return status
    }

    /// `criteria: [{text, done?}]`. 없으면 빈 배열. 문자열 항목도 받는다.
    func criteria(_ args: JSONValue) throws -> [Criterion] {
        guard let raw = args["criteria"], !raw.isNull else { return [] }
        guard let items = raw.arrayValue else { throw MCPToolError("criteria는 배열") }
        return try items.map { item in
            if let text = item.stringValue { return Criterion(text) }
            guard let text = item["text"]?.stringValue else { throw MCPToolError("criteria 항목에 text가 필요함") }
            return Criterion(text, isDone: item["done"]?.boolValue ?? false)
        }
    }

    // MARK: - 조회

    func allProjects() -> [Project] {
        (try? context.fetch(FetchDescriptor<Project>())) ?? []
    }

    /// `project`: 키(대소문자 무시) 또는 폴더 경로(가장 가까운 상위 rootPath).
    func resolveProject(_ args: JSONValue) throws -> Project {
        let raw = try requiredString(args, "project").trimmingCharacters(in: .whitespaces)
        let projects = allProjects().filter { $0.archivedAt == nil }
        if let project = projects.first(where: { $0.key.caseInsensitiveCompare(raw) == .orderedSame }) {
            return project
        }
        if raw.contains("/") || raw.hasPrefix("~"),
           let project = ProjectMatcher.project(for: raw, in: projects, home: home) {
            return project
        }
        throw MCPToolError("프로젝트 없음: \(raw)")
    }

    func resolveCard(_ args: JSONValue) throws -> Card {
        try findCard(try requiredString(args, "id"))
    }

    /// "PRB-1" → 카드. 키는 대소문자 무시.
    func findCard(_ displayID: String) throws -> Card {
        guard let (key, number) = Self.parseCardID(displayID) else {
            throw MCPToolError("카드 ID 형식이 아님: \(displayID) (예: PRB-1)")
        }
        guard let project = allProjects().first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }),
              let card = project.cards?.first(where: { $0.number == number })
        else { throw MCPToolError("카드 없음: \(displayID)") }
        return card
    }

    static func parseCardID(_ raw: String) -> (key: String, number: Int)? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 2, (2...5).contains(parts[0].count), parts[0].allSatisfy({ $0.isASCII && $0.isLetter }),
              let number = Int(parts[1]), number > 0
        else { return nil }
        return (String(parts[0]), number)
    }

    func fetchSession(_ id: String) -> Session? {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - 결과 JSON

    func projectJSON(_ project: Project) -> JSONValue {
        [
            "key": .string(project.key),
            "name": .string(project.name),
            "summary": .string(project.summary),
            "rootPath": .string(project.rootPath),
        ]
    }

    func cardJSON(_ card: Card) -> JSONValue {
        let date = now()
        let working = card.openCardSessions.compactMap(\.session)
            .filter { SessionRules.state(of: $0, now: date, stallTimeout: stallTimeout) != .ended }
        var json: [String: JSONValue] = [
            "id": .string(card.displayID),
            "title": .string(card.title),
            "kind": .string(card.kind.rawValue),
            "status": .string(card.status.rawValue),
            "criteria": .array(card.criteria.map { ["text": .string($0.text), "done": .bool($0.isDone)] }),
            "updatedAt": JSONValue(card.updatedAt),
        ]
        if let parent = card.parent { json["parentId"] = .string(parent.displayID) }
        if !working.isEmpty { json["sessions"] = .array(working.map(sessionJSON)) }
        return .object(json)
    }

    func sessionJSON(_ session: Session) -> JSONValue {
        var json: [String: JSONValue] = [
            "sessionId": .string(session.id),
            "provider": .string(session.provider.rawValue),
            "kind": .string(session.kind.rawValue),
            "state": .string(SessionRules.state(of: session, now: now(), stallTimeout: stallTimeout).rawValue),
            "activity": .string(SessionActivityRules.activity(session, now: now(), timeout: stallTimeout).rawValue),
            "activityLabel": .string(SessionFormat.activityText(session, now: now())),
        ]
        if let name = session.agentName { json["agentName"] = .string(name) }
        return .object(json)
    }

    func eventJSON(_ event: Event) -> JSONValue {
        var payload: [String: JSONValue] = [:]
        for (key, value) in event.payloadValues {
            switch value {
            case .string(let s): payload[key] = .string(s)
            case .int(let i): payload[key] = JSONValue(i)
            case .bool(let b): payload[key] = .bool(b)
            }
        }
        var json: [String: JSONValue] = ["at": JSONValue(event.at), "type": .string(event.type.rawValue)]
        if !payload.isEmpty { json["payload"] = .object(payload) }
        return .object(json)
    }
}
