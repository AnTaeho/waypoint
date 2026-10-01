import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// `Tests/Fixtures/mcp/<name>.json` 원문(Claude Code 2.1.283이 실제로 보낸 본문).
func mcpFixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/mcp"),
        "픽스처 없음: \(name)"
    )
    return try Data(contentsOf: url)
}

/// PRB 프로젝트(`~/probe`)와 live 메인 세션 하나를 갖춘 MCP 서버.
struct MCPHarness {
    let container: ModelContainer
    let context: ModelContext
    let server: MCPServer
    let project: Project
    let session: Session
    static let sessionID = "5e1f0c2a-0000-4000-8000-000000000001"

    init() throws {
        let (container, context) = try makeContext()
        self.container = container
        self.context = context
        let project = Project(key: "PRB", name: "probe", rootPath: "~/probe", createdAt: t0)
        context.insert(project)
        self.project = project
        self.session = makeSession(context, project, id: Self.sessionID, startedAt: t0, lastSeenAt: t0)
        try context.save()
        self.server = MCPServer(context: context, home: "/Users/me", now: { t0 + 60 })
    }

    func card(_ number: Int) -> Card? { project.cards?.first { $0.number == number } }

    /// tools/call → (결과 JSON, isError)
    /// 실패한 호출은 저장 안 된 변경을 되돌리므로, 테스트가 만든 것을 먼저 저장한다.
    func call(_ name: String, _ arguments: JSONValue) throws -> (JSONValue, Bool) {
        try context.save()
        let reply = try #require(server.handle([
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": ["name": .string(name), "arguments": arguments],
        ]))
        let result = try #require(reply["result"], "결과 없음: \(reply.serializedString)")
        let text = try #require(result["content"]?.arrayValue?.first?["text"]?.stringValue)
        let parsed = try #require(JSONValue.parse(Data(text.utf8)))
        return (parsed, result["isError"]?.boolValue ?? false)
    }

    func ok(_ name: String, _ arguments: JSONValue) throws -> JSONValue {
        let (value, isError) = try call(name, arguments)
        #expect(!isError, "\(name) 실패: \(value.serializedString)")
        return value
    }

    func fails(_ name: String, _ arguments: JSONValue) throws -> String {
        let (value, isError) = try call(name, arguments)
        #expect(isError, "\(name)가 실패해야 함: \(value.serializedString)")
        return value["error"]?.stringValue ?? ""
    }
}

func mcpRequest(_ body: String, method: String = "POST", headers: [String: String] = [:]) -> HTTPRequest {
    HTTPRequest(method: method, path: "/mcp", headers: headers, body: Data(body.utf8))
}

@Suite struct MCPRouterTests {
    let h: MCPHarness
    init() throws { h = try MCPHarness() }

    func respond(_ request: HTTPRequest) -> HTTPResponse {
        MCPRouter.respond(to: request) { h.server.handle($0) }
    }

    func body(_ r: HTTPResponse) throws -> JSONValue {
        try #require(JSONValue.parse(r.body), "JSON 아님: \(String(decoding: r.body, as: UTF8.self))")
    }

    @Test func realInitializeGetsSessionIdAndEchoedVersion() throws {
        let r = respond(HTTPRequest(method: "POST", path: "/mcp", headers: [:], body: try mcpFixture("real-initialize")))
        #expect(r.status == 200)
        #expect(r.contentType == "application/json")
        #expect(r.headers[MCPRouter.sessionIdHeader]?.isEmpty == false)
        let json = try body(r)
        #expect(json["id"] == 0)
        #expect(json["result"]?["protocolVersion"] == "2025-11-25")
        #expect(json["result"]?["serverInfo"]?["name"] == "waypoint")
        #expect(json["result"]?["capabilities"]?["tools"] != nil)
    }

    @Test func unknownClientVersionGetsOurLatest() throws {
        let r = respond(mcpRequest(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        #expect(try body(r)["result"]?["protocolVersion"] == .string(MCPRouter.latestVersion))
    }

    /// Claude Code는 새 방식(2026-07-28) `server/discover`를 먼저 보내고, 본문 없는 400을 받으면 initialize로 내려온다.
    /// 본문에 JSON-RPC 오류를 실으면 새 방식 서버로 오인하므로 비워 둔다.
    @Test func modernProbeGetsEmpty400() throws {
        let probe = HTTPRequest(method: "POST", path: "/mcp",
                                headers: ["mcp-protocol-version": "2026-07-28", "mcp-method": "server/discover"],
                                body: try mcpFixture("real-server-discover"))
        let r = respond(probe)
        #expect(r.status == 400)
        #expect(r.body.isEmpty)
        // 협상한 옛 버전 머리는 받는다
        let ok = respond(mcpRequest(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#, headers: ["mcp-protocol-version": "2025-06-18"]))
        #expect(ok.status == 200)
    }

    @Test func initializedNotificationIs202() {
        let r = respond(mcpRequest(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        #expect(r.status == 202)
        #expect(r.body.isEmpty)
    }

    @Test func toolsListShape() throws {
        // 세션 ID가 없거나 모르는 값이어도 받는다(앱 재시작 뒤에도 클라이언트가 계속 쓰게)
        let r = respond(mcpRequest(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#, headers: ["mcp-session-id": "unknown"]))
        #expect(r.status == 200)
        let tools = try #require(try body(r)["result"]?["tools"]?.arrayValue)
        let names = tools.compactMap { $0["name"]?.stringValue }
        #expect(names == ["project_resolve", "project_init", "session_bind", "card_list", "card_get", "card_create", "card_start",
                          "card_update", "card_note", "card_handoff", "card_evidence"])
        for tool in tools {
            #expect(tool["description"]?.stringValue?.isEmpty == false)
            #expect(tool["inputSchema"]?["type"] == "object")
            let props = try #require(tool["inputSchema"]?["properties"]?.objectValue)
            for required in tool["inputSchema"]?["required"]?.arrayValue ?? [] {
                #expect(props[required.stringValue ?? ""] != nil, "\(tool["name"]!) \(required)")
            }
        }
        let start = try #require(tools.first { $0["name"] == "card_start" })
        #expect(start["inputSchema"]?["required"] == ["id", "sessionId"])
    }

    @Test func pingAndUnknownMethod() throws {
        #expect(try body(respond(mcpRequest(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)))["result"] == [:])
        let unknown = try body(respond(mcpRequest(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)))
        #expect(unknown["error"]?["code"] == -32601)
        #expect(unknown["id"] == 4)
    }

    @Test func parseErrorAndInvalidRequest() throws {
        let bad = respond(mcpRequest("{not json"))
        #expect(bad.status == 400)
        let json = try body(bad)
        #expect(json["error"]?["code"] == -32700)
        #expect(json["id"] == .null)

        let invalid = try body(respond(mcpRequest(#"{"jsonrpc":"1.0","id":5,"method":"ping"}"#)))
        #expect(invalid["error"]?["code"] == -32600)
        let empty = try body(respond(mcpRequest("[]")))
        #expect(empty["error"]?["code"] == -32600)
    }

    @Test func batchKeepsOrderAndSkipsNotifications() throws {
        let r = respond(mcpRequest(#"""
        [{"jsonrpc":"2.0","id":1,"method":"ping"},
         {"jsonrpc":"2.0","method":"notifications/initialized"},
         {"jsonrpc":"2.0","id":2,"method":"nope"},
         {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"card_list","arguments":{"project":"PRB"}}}]
        """#))
        let replies = try #require(try body(r).arrayValue)
        #expect(replies.map { $0["id"] } == [1, 2, 3])
        #expect(replies[0]["result"] == [:])
        #expect(replies[1]["error"]?["code"] == -32601)
        #expect(replies[2]["result"]?["isError"] == false)

        let onlyNotes = respond(mcpRequest(#"[{"jsonrpc":"2.0","method":"notifications/initialized"}]"#))
        #expect(onlyNotes.status == 202)
    }

    @Test func originCheck() {
        let evil = respond(mcpRequest("{}", headers: ["origin": "http://evil.example"]))
        #expect(evil.status == 403)
        let rebinding = respond(mcpRequest("{}", headers: ["origin": "http://127.0.0.1.evil.example:47821"]))
        #expect(rebinding.status == 403)
        for ok in ["http://localhost:3000", "http://127.0.0.1:47821", "http://[::1]:8080"] {
            let r = respond(mcpRequest(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["origin": ok]))
            #expect(r.status == 200, "\(ok)")
        }
    }

    @Test func getAndDeleteAre405() {
        #expect(respond(mcpRequest("", method: "GET")).status == 405)
        #expect(respond(mcpRequest("", method: "DELETE")).status == 405)
        #expect(MCPRouter.respond(to: HTTPRequest(method: "POST", path: "/mcp/x", headers: [:], body: Data())) { _ in nil } == .notFound)
    }

    @Test func unknownToolIsProtocolError() throws {
        let reply = try #require(h.server.handle(["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                  "params": ["name": "project_delete", "arguments": [:]]]))
        #expect(reply["error"]?["code"] == -32602)
    }

    @Test func responseSerializesSessionHeader() {
        let r = HTTPResponse.json(Data("{}".utf8), headers: ["Mcp-Session-Id": "abc"])
        let text = String(decoding: r.serialized(), as: UTF8.self)
        #expect(text == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nMcp-Session-Id: abc\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        #expect(String(decoding: HTTPResponse.accepted.serialized(), as: UTF8.self)
                == "HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }
}

@Suite struct MCPToolTests {
    let h: MCPHarness
    init() throws { h = try MCPHarness() }

    @Test func projectResolve() throws {
        let found = try h.ok("project_resolve", ["cwd": "/Users/me/probe/src"])
        #expect(found["key"] == "PRB")
        #expect(try h.ok("project_resolve", ["cwd": "/Users/me/elsewhere"]) == .null)
        _ = try h.fails("project_resolve", [:])
    }

    @Test func createDefaultsAndIdea() throws {
        let task = try h.ok("card_create", ["project": "prb", "title": "CSV 파서", "sessionId": .string(MCPHarness.sessionID),
                                            "criteria": [["text": "테스트 통과"], "문서"]])
        #expect(task["id"] == "PRB-1")
        #expect(task["kind"] == "task")
        #expect(task["status"] == "next")
        let card = try #require(h.card(1))
        #expect(card.origin == .claude)
        #expect(card.originSessionId == MCPHarness.sessionID)
        #expect(card.criteria == [Criterion("테스트 통과"), Criterion("문서")])
        #expect(events(card, .cardCreated).count == 1)

        // 폴더 경로로도, idea는 status 기본값이 idea
        let idea = try h.ok("card_create", ["project": "/Users/me/probe", "title": "CSV 내보내기", "kind": "idea"])
        #expect(idea["id"] == "PRB-2")
        #expect(idea["status"] == "idea")

        let child = try h.ok("card_create", ["project": "PRB", "title": "하위", "parentId": "PRB-1"])
        #expect(child["parentId"] == "PRB-1")
    }

    @Test func createErrors() throws {
        #expect(try h.fails("card_create", ["project": "NOPE", "title": "x"]).contains("프로젝트 없음"))
        _ = try h.fails("card_create", ["project": "PRB", "title": "  "])
        _ = try h.fails("card_create", ["project": "PRB", "title": "x", "status": "active"])
        _ = try h.fails("card_create", ["project": "PRB", "title": "x", "kind": "epic"])
        _ = try h.fails("card_create", ["project": "PRB", "title": "x", "parentId": "PRB-99"])
        // 실패한 호출은 되돌린다(번호도 그대로)
        #expect(h.project.cards?.isEmpty == true)
        #expect(h.project.nextCardNumber == 1)
    }

    @Test func listFiltersAndSorts() throws {
        let c1 = h.project.makeCard(in: h.context, title: "하나", status: .next, at: t0)
        h.project.makeCard(in: h.context, title: "둘 아이디어", status: .idea, at: t0)
        h.project.makeCard(in: h.context, title: "셋 끝", status: .done, at: t0)
        CardLifecycle.attach(c1, h.session, at: t0, in: h.context)
        h.project.makeCard(in: h.context, title: "넷", status: .next, at: t0)

        let all = try h.ok("card_list", ["project": "PRB"])["cards"]?.arrayValue ?? []
        #expect(all.map { $0["id"] } == ["PRB-1", "PRB-4", "PRB-2"])
        #expect(all[0]["sessions"]?.arrayValue?.first?["sessionId"] == .string(MCPHarness.sessionID))
        let done = try h.ok("card_list", ["project": "PRB", "status": "done"])["cards"]?.arrayValue ?? []
        #expect(done.map { $0["id"] } == ["PRB-3"])
        let query = try h.ok("card_list", ["project": "PRB", "query": "아이디어"])["cards"]?.arrayValue ?? []
        #expect(query.map { $0["id"] } == ["PRB-2"])
        _ = try h.fails("card_list", ["project": "PRB", "status": "doing"])
    }

    @Test func getIncludesEvents() throws {
        _ = try h.ok("card_create", ["project": "PRB", "title": "a"])
        _ = try h.ok("card_note", ["id": "PRB-1", "text": "파서는 정규식으로"])
        let card = try h.ok("card_get", ["id": "prb-1"])
        #expect(card["title"] == "a")
        #expect(card["origin"] == "claude")
        let types = card["recentEvents"]?.arrayValue?.compactMap { $0["type"]?.stringValue } ?? []
        #expect(types.contains("note"))
        #expect(types.contains("card.created"))
        #expect(try h.fails("card_get", ["id": "PRB-9"]).contains("카드 없음"))
        #expect(try h.fails("card_get", ["id": "PRB1"]).contains("형식"))
    }

    @Test func startMarksActiveAndSwitchRestores() throws {
        let a = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        let b = h.project.makeCard(in: h.context, title: "b", status: .idea, at: t0)
        let sid = JSONValue.string(MCPHarness.sessionID)

        let first = try h.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        #expect(first["card"]?["status"] == "active")
        #expect(first["detached"] == [])
        #expect(a.status == .active)
        #expect(CardRules.workState(of: a, now: t0 + 60) == .live)

        // 주제 전환: a는 연결이 풀리고 원래 상태(next)로, done이 되지 않는다
        let second = try h.ok("card_start", ["id": "PRB-2", "sessionId": sid])
        #expect(second["detached"] == ["PRB-1"])
        #expect(a.status == .next)
        #expect(a.openCardSessions.isEmpty)
        #expect(b.status == .active)
        #expect(b.statusBeforeActive == "idea")

        // 세션이 끝나면 b도 원래 상태(idea)로
        CardLifecycle.detachAll(h.session, at: t0 + 120, in: h.context)
        #expect(b.status == .idea)
        #expect(a.doneAt == nil && b.doneAt == nil)
    }

    @Test func startSameCardTwiceIsNoop() throws {
        let a = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        let sid = JSONValue.string(MCPHarness.sessionID)
        _ = try h.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        let again = try h.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        #expect(again["detached"] == [])
        #expect(a.openCardSessions.count == 1)
        #expect(events(a, .cardAttached).count == 1)
    }

    @Test func startReportsOtherSessionsAndSubagent() throws {
        let a = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        let other = makeSession(h.context, h.project, id: "other", startedAt: t0, lastSeenAt: t0)
        CardLifecycle.attach(a, other, at: t0, in: h.context)
        let r = try h.ok("card_start", ["id": "PRB-1", "sessionId": .string(MCPHarness.sessionID)])
        #expect(r["otherSessions"]?.arrayValue?.map { $0["sessionId"] } == ["other"])

        // 서브에이전트 세션 ID면 그 하위 세션에 붙는다
        let sub = makeSession(h.context, h.project, id: "ad5a8ca20b7faa5f7", startedAt: t0, lastSeenAt: t0, parent: h.session)
        let child = h.project.makeCard(in: h.context, title: "하위", status: .next, at: t0)
        _ = try h.ok("card_start", ["id": "PRB-2", "sessionId": "ad5a8ca20b7faa5f7"])
        #expect(child.openCardSessions.compactMap(\.session).map(\.id) == [sub.id])
        #expect(a.openCardSessions.count == 2) // 부모 세션 연결은 그대로
    }

    @Test func startErrors() throws {
        h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        #expect(try h.fails("card_start", ["id": "PRB-1", "sessionId": "nope"]).contains("세션 없음"))
        let ended = makeSession(h.context, h.project, id: "ended", startedAt: t0)
        ended.endedAt = t0
        #expect(try h.fails("card_start", ["id": "PRB-1", "sessionId": "ended"]).contains("끝난 세션"))
        let elsewhere = Project(key: "OTH", name: "other", rootPath: "~/other")
        h.context.insert(elsewhere)
        _ = makeSession(h.context, elsewhere, id: "oth-session")
        #expect(try h.fails("card_start", ["id": "PRB-1", "sessionId": "oth-session"]).contains("프로젝트"))
        _ = try h.fails("card_start", ["id": "PRB-1"])
        #expect(h.card(1)?.status == .next)
    }

    @Test func updateRejectsActiveAllowsDone() throws {
        let a = h.project.makeCard(in: h.context, title: "a", status: .next, criteria: [Criterion("x")], at: t0)
        #expect(try h.fails("card_update", ["id": "PRB-1", "status": "active"]).contains("card_start"))
        #expect(a.status == .next)

        let r = try h.ok("card_update", ["id": "PRB-1", "title": "a2", "body": "본문",
                                         "criteria": [["text": "x", "done": true], ["text": "y"]]])
        #expect(r["title"] == "a2")
        #expect(a.body == "본문")
        #expect(a.criteria == [Criterion("x", isDone: true), Criterion("y")])

        _ = try h.ok("card_update", ["id": "PRB-1", "status": "done"])
        #expect(a.status == .done)
        #expect(a.doneAt == t0 + 60)
        _ = try h.fails("card_update", ["id": "PRB-1", "status": "finished"])
    }

    @Test func noteAndHandoff() throws {
        let a = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        _ = try h.ok("card_note", ["id": "PRB-1", "text": "막힘: 인코딩"])
        #expect(events(a, .note).last?.payloadValues["text"] == "막힘: 인코딩")
        _ = try h.fails("card_note", ["id": "PRB-1", "text": " "])

        let r = try h.ok("card_handoff", ["id": "PRB-1", "nextSessionNote": "파서까지 함. 남은 것: 테스트"])
        #expect(r["nextSessionNote"] == "파서까지 함. 남은 것: 테스트")
        #expect(a.nextSessionNote == "파서까지 함. 남은 것: 테스트")
        let handoff = events(a, .note).first { $0.payloadValues["kind"] == "handoff" }
        #expect(handoff?.payloadValues["text"] == "파서까지 함. 남은 것: 테스트")
    }
}
