import Foundation
import SwiftData

/// 도구 실패. 결과에 `isError: true`로 실린다.
public struct MCPToolError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// SPEC 7장 도구 구현. 저장(save)은 호출 쪽(`MCPServer`)에서 한다.
/// 넘겨받은 context가 속한 액터에서만 부른다.
public final class MCPTools {
    public let context: ModelContext
    /// `~` 펼치기(프로젝트 매칭). 테스트에서 바꾼다.
    public let home: String
    public let now: () -> Date
    public var stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    /// `card_get`에 싣는 최근 기록 수
    public static let recentEventLimit = 20

    public init(context: ModelContext, home: String = NSHomeDirectory(), now: @escaping () -> Date = Date.init) {
        self.context = context
        self.home = home
        self.now = now
    }

    public func call(_ name: String, _ args: JSONValue) throws -> JSONValue {
        switch name {
        case "project_resolve": return try projectResolve(args)
        case "card_list": return try cardList(args)
        case "card_get": return try cardGet(args)
        case "card_create": return try cardCreate(args)
        case "card_start": return try cardStart(args)
        case "card_update": return try cardUpdate(args)
        case "card_note": return try cardNote(args)
        case "card_handoff": return try cardHandoff(args)
        default: throw MCPToolError("알 수 없는 도구: \(name)")
        }
    }

    // MARK: - 도구

    func projectResolve(_ args: JSONValue) throws -> JSONValue {
        let cwd = try requiredString(args, "cwd")
        guard let project = ProjectMatcher.project(for: cwd, in: allProjects(), home: home) else { return .null }
        return projectJSON(project)
    }

    func cardList(_ args: JSONValue) throws -> JSONValue {
        let project = try resolveProject(args)
        let status = try optionalStatus(args, "status")
        let query = optionalString(args, "query")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let order: [CardStatus] = [.active, .next, .idea, .done, .archived]
        let cards = (project.cards ?? [])
            .filter { card in
                if let status { return card.status == status }
                return card.status != .done && card.status != .archived
            }
            .filter { card in
                guard let query, !query.isEmpty else { return true }
                return [card.displayID, card.title, card.body].contains { $0.lowercased().contains(query) }
            }
            .sorted {
                let a = order.firstIndex(of: $0.status) ?? 0, b = order.firstIndex(of: $1.status) ?? 0
                return a != b ? a < b : $0.number < $1.number
            }
        return ["project": .string(project.key), "cards": .array(cards.map(cardJSON))]
    }

    func cardGet(_ args: JSONValue) throws -> JSONValue {
        let card = try resolveCard(args)
        let events = (card.events ?? []).sorted { $0.at > $1.at }.prefix(Self.recentEventLimit)
        guard case .object(var json) = cardJSON(card) else { return cardJSON(card) }
        json["body"] = .string(card.body)
        json["origin"] = .string(card.origin.rawValue)
        json["nextSessionNote"] = JSONValue(card.nextSessionNote)
        json["children"] = .array((card.children ?? []).sorted { $0.number < $1.number }.map { .string($0.displayID) })
        json["createdAt"] = JSONValue(card.createdAt)
        json["recentEvents"] = .array(events.map(eventJSON))
        return .object(json)
    }

    func cardCreate(_ args: JSONValue) throws -> JSONValue {
        let project = try resolveProject(args)
        let title = try requiredString(args, "title").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MCPToolError("title이 비어 있음") }
        let kind: CardKind
        if let raw = optionalString(args, "kind") {
            guard let k = CardKind(rawValue: raw) else { throw MCPToolError("kind는 task·idea·bug 중 하나") }
            kind = k
        } else {
            kind = .task
        }
        let status = try optionalStatus(args, "status") ?? (kind == .idea ? .idea : .next)
        guard status != .active else { throw MCPToolError("active로는 만들 수 없음. 만든 뒤 card_start") }
        var parent: Card?
        if let parentId = optionalString(args, "parentId") {
            parent = try findCard(parentId)
            guard parent?.project === project else { throw MCPToolError("parentId는 같은 프로젝트 카드여야 함") }
        }
        let date = now()
        let sessionId = optionalString(args, "sessionId")
        let card = project.makeCard(
            in: context, title: title, kind: kind, status: status,
            body: optionalString(args, "body") ?? "", origin: .claude, originSessionId: sessionId,
            parent: parent, criteria: try criteria(args), at: date
        )
        let session = sessionId.flatMap(fetchSession)
        Event.record(.cardCreated, in: context, project: project, card: card, session: session, at: date,
                     payload: ["origin": .string(CardOrigin.claude.rawValue), "status": .string(status.rawValue)])
        return cardJSON(card)
    }

    func cardStart(_ args: JSONValue) throws -> JSONValue {
        let card = try resolveCard(args)
        let sessionId = try requiredString(args, "sessionId")
        guard let session = fetchSession(sessionId) else {
            throw MCPToolError("세션 없음: \(sessionId). 주입된 Waypoint 블록의 sessionId를 쓴다")
        }
        guard session.endedAt == nil else { throw MCPToolError("끝난 세션: \(sessionId)") }
        guard session.project === card.project else { throw MCPToolError("세션과 카드의 프로젝트가 다름") }
        guard card.status != .archived else { throw MCPToolError("보관된 카드") }

        let date = now()
        // 주제 전환: 이 세션의 다른 열린 카드 연결을 먼저 푼다(카드는 작업 전 상태로 돌아간다).
        var detached: [String] = []
        var seen = Set<ObjectIdentifier>()
        for other in session.openCardSessions.compactMap(\.card)
        where other !== card && seen.insert(ObjectIdentifier(other)).inserted {
            CardLifecycle.detach(other, session, at: date, in: context)
            detached.append(other.displayID)
        }
        CardLifecycle.attach(card, session, at: date, in: context)
        if date > session.lastSeenAt { session.lastSeenAt = date }

        let others = card.openCardSessions.compactMap(\.session)
            .filter { $0 !== session && SessionRules.state(of: $0, now: date, stallTimeout: stallTimeout) != .ended }
        return [
            "card": cardJSON(card),
            "sessionId": .string(session.id),
            "detached": .array(detached.map { .string($0) }),
            "otherSessions": .array(others.map(sessionJSON)),
        ]
    }

    func cardUpdate(_ args: JSONValue) throws -> JSONValue {
        let card = try resolveCard(args)
        let date = now()
        if let title = optionalString(args, "title") {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MCPToolError("title이 비어 있음") }
            card.title = trimmed
            card.updatedAt = date
        }
        if let body = optionalString(args, "body") {
            card.body = body
            card.updatedAt = date
        }
        if args["criteria"] != nil {
            card.criteria = try criteria(args)
            card.updatedAt = date
        }
        if let status = try optionalStatus(args, "status") {
            guard status != .active else { throw MCPToolError("active는 card_start로만") }
            try CardLifecycle.move(card, to: status, at: date, in: context)
        }
        return cardJSON(card)
    }

    func cardNote(_ args: JSONValue) throws -> JSONValue {
        let card = try resolveCard(args)
        let text = try requiredString(args, "text").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MCPToolError("text가 비어 있음") }
        Event.record(.note, in: context, card: card, at: now(), payload: ["text": .string(text)])
        return ["id": .string(card.displayID), "noted": true]
    }

    func cardHandoff(_ args: JSONValue) throws -> JSONValue {
        let card = try resolveCard(args)
        let note = try requiredString(args, "nextSessionNote").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { throw MCPToolError("nextSessionNote가 비어 있음") }
        let date = now()
        card.nextSessionNote = note
        card.updatedAt = date
        Event.record(.note, in: context, card: card, at: date,
                     payload: ["kind": .string(Self.handoffNoteKind), "text": .string(note)])
        return ["id": .string(card.displayID), "nextSessionNote": .string(note)]
    }

    /// `note` 이벤트 payload의 `kind` 값: 다음 세션 메모 저장.
    public static let handoffNoteKind = "handoff"
}
