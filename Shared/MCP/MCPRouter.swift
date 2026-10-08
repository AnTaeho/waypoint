import Foundation

/// `/mcp` 엔드포인트의 HTTP 층(MCP Streamable HTTP 중 필요한 부분만, SPEC 7장).
/// POST에 JSON-RPC 메시지 하나 또는 배치, 응답은 `application/json` 하나(SSE 없음).
/// 소켓 없이 테스트할 수 있게 요청 → 응답만 다룬다. 메시지 처리는 `handle`에 맡긴다.
public enum MCPRouter {
    public static let path = "/mcp"

    /// 받는 프로토콜 버전(초기화 방식, 새것부터). 첫째가 우리 최신.
    public static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public static var latestVersion: String { supportedVersions[0] }

    public static let sessionIdHeader = "Mcp-Session-Id"

    public static func matches(_ path: String) -> Bool { path == Self.path }

    /// `Origin`이 없거나 루프백이면 허용(DNS 리바인딩 방어).
    public static func isAllowedOrigin(_ origin: String?) -> Bool {
        guard let origin, !origin.isEmpty else { return true }
        guard let host = URLComponents(string: origin)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
    }

    /// - Parameter handle: JSON-RPC 메시지 하나 → 응답(알림·클라이언트 응답이면 nil)
    public static func respond(to request: HTTPRequest, handle: (JSONValue) -> JSONValue?) -> HTTPResponse {
        guard matches(request.path) else { return .notFound }
        guard isAllowedOrigin(request.headers["origin"]) else { return .forbidden }
        guard request.method == "POST" else { return .methodNotAllowed }
        // 모르는 버전(2026-07-28 같은 새 방식 포함)은 본문 없는 400. Claude Code는 이것을 보고 initialize로 내려온다.
        if let version = request.headers["mcp-protocol-version"], !supportedVersions.contains(version) {
            return .badRequest
        }
        guard let message = JSONValue.parse(request.body) else {
            return .json(JSONRPC.error(id: .null, code: JSONRPC.parseError, message: "Parse error").serialized(), status: 400)
        }

        let replies: [JSONValue]
        let isBatch: Bool
        if case .array(let items) = message {
            guard !items.isEmpty else {
                return .json(JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, message: "Empty batch").serialized())
            }
            replies = items.compactMap(handle)
            isBatch = true
        } else {
            replies = handle(message).map { [$0] } ?? []
            isBatch = false
        }
        guard !replies.isEmpty else { return .accepted }

        // initialize에 성공했으면 세션 ID를 준다. 이후 요청에서 이 값은 검사하지 않는다(앱을 다시 켜도 그대로 쓰게).
        var headers: [String: String] = [:]
        if initializeSucceeded(message, replies) {
            headers[sessionIdHeader] = UUID().uuidString.lowercased()
        }
        let body: JSONValue = isBatch ? .array(replies) : replies[0]
        return .json(body.serialized(), headers: headers)
    }

    /// 응답을 미루는 도구 호출(`MCPTools.deferredTools`) 하나면 그 메시지. 배치·다른 메서드·거절할 요청은 nil(`respond`로).
    public static func deferredCall(_ request: HTTPRequest) -> JSONValue? {
        guard matches(request.path), isAllowedOrigin(request.headers["origin"]), request.method == "POST",
              request.headers["mcp-protocol-version"].map(supportedVersions.contains) ?? true,
              let message = JSONValue.parse(request.body), message["method"] == "tools/call",
              let name = message["params"]?["name"]?.stringValue, MCPTools.deferredTools.contains(name)
        else { return nil }
        return message
    }

    private static func initializeSucceeded(_ message: JSONValue, _ replies: [JSONValue]) -> Bool {
        let requests = message.arrayValue ?? [message]
        let ids = requests.filter { $0["method"]?.stringValue == "initialize" }.compactMap { $0["id"] }
        return replies.contains { reply in reply["result"] != nil && ids.contains { $0 == reply["id"] } }
    }
}

/// JSON-RPC 2.0 메시지 만들기.
public enum JSONRPC {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    public static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": JSONValue(code), "message": .string(message)]]
    }
}
