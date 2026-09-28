import Foundation
import Testing
@testable import WaypointKit

@Suite struct HTTPRequestParserTests {
    func raw(_ s: String) -> Data { Data(s.utf8) }

    @Test func parsesPostWithBody() throws {
        let body = #"{"session_id":"s"}"#
        let text = "POST /hooks/SessionStart?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .request(let r) = HTTPRequestParser.parse(raw(text)) else { Issue.record("요청이 아님"); return }
        #expect(r.method == "POST")
        #expect(r.path == "/hooks/SessionStart")
        #expect(r.headers["content-type"] == "application/json")
        #expect(String(data: r.body, encoding: .utf8) == body)
    }

    @Test func incompleteUntilBodyArrives() {
        let head = "POST /hooks/Stop HTTP/1.1\r\nContent-Length: 10\r\n\r\n"
        #expect(HTTPRequestParser.parse(raw("POST /hooks/Stop HTTP/1.1\r\nContent-")) == .incomplete)
        #expect(HTTPRequestParser.parse(raw(head + "12345")) == .incomplete)
        guard case .request(let r) = HTTPRequestParser.parse(raw(head + "1234567890")) else {
            Issue.record("요청이 아님"); return
        }
        #expect(r.body.count == 10)
    }

    @Test func multibyteBodyUsesByteLength() throws {
        let body = #"{"prompt":"한글"}"#
        let text = "POST /hooks/UserPromptSubmit HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .request(let r) = HTTPRequestParser.parse(raw(text)) else { Issue.record("요청이 아님"); return }
        #expect(String(data: r.body, encoding: .utf8) == body)
    }

    @Test func rejectsGarbageAndHugeBodies() {
        #expect(HTTPRequestParser.parse(raw("hello\r\n\r\n")) == .invalid)
        #expect(HTTPRequestParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n")) == .invalid)
        #expect(HTTPRequestParser.parse(raw("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")) == .invalid)
        #expect(HTTPRequestParser.parse(raw("POST / HTTP/1.1\r\nBadHeader\r\n\r\n")) == .invalid)
    }

    @Test func serializesResponses() {
        let ok = String(data: HTTPResponse.text("안녕").serialized(), encoding: .utf8)
        #expect(ok == "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: 6\r\nConnection: close\r\n\r\n안녕")
        let none = String(data: HTTPResponse.noContent.serialized(), encoding: .utf8)
        #expect(none == "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
    }
}

@Suite struct HookRouterTests {
    func request(_ method: String, _ path: String, _ body: String = "{}") -> HTTPRequest {
        HTTPRequest(method: method, path: path, headers: [:], body: Data(body.utf8))
    }

    @Test func sessionStartReturnsText() {
        var seen: [String] = []
        let r = HookRouter.respond(to: request("POST", "/hooks/SessionStart")) { event, _, _ in
            seen.append(event); return "컨텍스트"
        }
        #expect(r == .text("컨텍스트"))
        #expect(seen == ["SessionStart"])
    }

    @Test func sessionStartWithoutTextIsEmpty200() {
        let r = HookRouter.respond(to: request("POST", "/hooks/SessionStart")) { _, _, _ in nil }
        #expect(r.status == 200)
        #expect(r.body.isEmpty)
    }

    @Test func otherEventsAre204() {
        let r = HookRouter.respond(to: request("POST", "/hooks/PostToolUse")) { _, _, _ in "무시됨" }
        #expect(r == .noContent)
    }

    /// 늦은 주입: UserPromptSubmit은 텍스트가 있을 때만 200, 없거나 비면 204.
    @Test func userPromptSubmitReturnsTextOnlyWhenPresent() {
        let with = HookRouter.respond(to: request("POST", "/hooks/UserPromptSubmit")) { _, _, _ in "Waypoint: LDG (가계부 앱)" }
        #expect(with == .text("Waypoint: LDG (가계부 앱)"))
        let none = HookRouter.respond(to: request("POST", "/hooks/UserPromptSubmit")) { _, _, _ in nil }
        #expect(none == .noContent)
        let empty = HookRouter.respond(to: request("POST", "/hooks/UserPromptSubmit")) { _, _, _ in "" }
        #expect(empty == .noContent)
    }

    @Test func claudePidHeader() throws {
        // 머리 이름은 파서가 소문자로 바꾼다
        let raw = "POST /hooks/Stop HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Waypoint-Claude-PID: 5287\r\nContent-Length: 2\r\n\r\n{}"
        guard case .request(let parsed) = HTTPRequestParser.parse(Data(raw.utf8)) else {
            Issue.record("요청을 못 읽음"); return
        }
        var seen: [Int?] = []
        _ = HookRouter.respond(to: parsed) { _, _, pid in seen.append(pid); return nil }
        _ = HookRouter.respond(to: request("POST", "/hooks/Stop")) { _, _, pid in seen.append(pid); return nil }
        #expect(seen == [5287, nil])
        for bad in ["", "abc", "0", "1", "-3", "12x"] {
            let r = HTTPRequest(method: "POST", path: "/hooks/Stop", headers: ["x-waypoint-claude-pid": bad], body: Data())
            #expect(HookRouter.claudePid(from: r) == nil, "\(bad)")
        }
    }

    @Test func wrongPathOrMethod() {
        var called = false
        func respond(_ method: String, _ path: String) -> HTTPResponse {
            HookRouter.respond(to: request(method, path)) { _, _, _ in called = true; return nil }
        }
        let mcp = respond("POST", "/mcp")
        let empty = respond("POST", "/hooks/")
        let dots = respond("POST", "/hooks/../x")
        let get = respond("GET", "/hooks/Stop")
        #expect(mcp == .notFound)
        #expect(empty == .notFound)
        #expect(dots == .notFound)
        #expect(get == .methodNotAllowed)
        #expect(called == false)
    }
}
