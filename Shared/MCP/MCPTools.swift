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
    /// `project_init` 초안을 두는 곳. 없으면 `project_init`은 실패한다.
    public var drafts: ProjectDraftQueue?
    let fileManager = FileManager.default
    /// 등록 프로젝트 폴더 → 로컬 git 작업 트리·origin(`project_resolve`의 `remote`, TRK-53). 테스트에서 바꾼다.
    public var localOrigin: (String) -> LocalOrigin? = { LocalOriginCache.shared.origin(for: $0) }
    /// `card_get`에 싣는 최근 기록 수
    public static let recentEventLimit = 20
    /// 응답 `overlaps`로 이미 알린 파일(`<내 세션 ID>|<상대 단위 메인 세션 ID>` → 파일). 메모리에만 둔다(TRK-17).
    var reportedOverlaps: [String: Set<String>] = [:]

    public init(
        context: ModelContext, home: String = NSHomeDirectory(), drafts: ProjectDraftQueue? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.home = home
        self.drafts = drafts
        self.now = now
    }

    public func call(_ name: String, _ args: JSONValue) throws -> JSONValue {
        switch name {
        case "project_resolve": return try projectResolve(args)
        case "project_init": return try projectInit(args)
        case "session_bind": return try sessionBind(args)
        case "card_list": return try cardList(args)
        case "card_get": return try cardGet(args)
        case "card_create": return try cardCreate(args)
        case "card_start": return withOverlaps(try cardStart(args), sessions: try overlapSessions(name, args))
        case "card_update": return withOverlaps(try cardUpdate(args), sessions: try overlapSessions(name, args))
        case "card_note": return withOverlaps(try cardNote(args), sessions: try overlapSessions(name, args))
        case "card_handoff": return withOverlaps(try cardHandoff(args), sessions: try overlapSessions(name, args))
        case "card_evidence": return withOverlaps(try cardEvidence(args), sessions: try overlapSessions(name, args))
        case "project_status": return withOverlaps(try projectStatus(args), sessions: try overlapSessions(name, args))
        case "work_file": return try workFile(args)
        default: throw MCPToolError("알 수 없는 도구: \(name)")
        }
    }

    // MARK: - 도구

    /// `remote`(원격·컨테이너 작업 트리의 git origin 주소)를 주면, `cwd`가 어떤 등록 폴더와도 맞지 않을 때 같은 원격 주소의
    /// 등록 프로젝트를 찾는다(훅과 같은 규칙, TRK-53). 작업 트리가 둘 이상이면 null.
    func projectResolve(_ args: JSONValue) throws -> JSONValue {
        let cwd = try requiredString(args, "cwd")
        let projects = allProjects()
        if let project = ProjectMatcher.project(for: cwd, in: projects, home: home) { return projectJSON(project) }
        guard let origin = optionalString(args, "remote")?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty,
              ProjectMatcher.nearest(for: cwd, in: projects, home: home) == nil,
              let local = RemoteMatcher.localCheckout(origin: origin, in: projects, home: home, localOrigin: localOrigin)
        else { return .null }
        // 원격 시작 폴더의 작업 트리 안 위치를 모르므로(작업 트리 최상위를 받지 않는다) 그 작업 트리의 가장 바깥 프로젝트
        let inside = projects.filter {
            $0.archivedAt == nil && ProjectMatcher.isInside(ProjectMatcher.normalize($0.rootPath, home: home), root: local)
        }
        guard let project = inside.min(by: { $0.rootPath.count < $1.rootPath.count }) else { return .null }
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
        let session = sessionId.flatMap(fetchSession)
        let requestedProvider = try provider(args)
        let origin = (session?.provider ?? requestedProvider).cardOrigin
        let card = project.makeCard(
            in: context, title: title, kind: kind, status: status,
            body: optionalString(args, "body") ?? "", origin: origin, originSessionId: sessionId,
            parent: parent, criteria: try criteria(args), at: date
        )
        Event.record(.cardCreated, in: context, project: project, card: card, session: session, at: date,
                     payload: ["origin": .string(origin.rawValue), "status": .string(status.rawValue)])
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
            let old = card.criteria
            card.criteria = try criteria(args)
            card.updatedAt = date
            CardEditing.recordCriteriaChanges(card, from: old, at: date, in: context)
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
