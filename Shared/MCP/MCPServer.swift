import Foundation
import SwiftData

/// JSON-RPC 메서드 처리: `initialize`, `ping`, `tools/list`, `tools/call`(SPEC 7장).
/// 넘겨받은 context가 속한 액터(앱에서는 메인 액터)에서만 부른다. Sendable이 아니다.
public final class MCPServer {
    public let tools: MCPTools
    public static let serverName = "waypoint"
    public static let serverVersion = "0.5.0"

    public init(
        context: ModelContext, home: String = NSHomeDirectory(), drafts: ProjectDraftQueue? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tools = MCPTools(context: context, home: home, drafts: drafts, now: now)
    }

    public var context: ModelContext { tools.context }

    /// 메시지 하나를 처리한다. 알림·클라이언트 응답이면 nil.
    public func handle(_ message: JSONValue) -> JSONValue? {
        guard case .object(let object) = message else {
            return JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, message: "Invalid Request")
        }
        let id = object["id"]
        guard object["jsonrpc"] == "2.0", let method = object["method"]?.stringValue else {
            // 클라이언트가 보낸 응답(결과·오류)은 받기만 한다.
            if object["method"] == nil, object["result"] != nil || object["error"] != nil { return nil }
            return JSONRPC.error(id: id ?? .null, code: JSONRPC.invalidRequest, message: "Invalid Request")
        }
        let params = object["params"] ?? [:]
        guard let id else {
            // 알림(notifications/initialized 등)은 받고 끝.
            return nil
        }
        switch id {
        case .string, .number: break
        default: return JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, message: "Invalid id")
        }

        switch method {
        case "initialize":
            return JSONRPC.result(id: id, initialize(params))
        case "ping":
            return JSONRPC.result(id: id, [:])
        case "tools/list":
            return JSONRPC.result(id: id, ["tools": .array(MCPTools.definitions.map(\.json))])
        case "tools/call":
            return callTool(id: id, params)
        default:
            return JSONRPC.error(id: id, code: JSONRPC.methodNotFound, message: "Method not found: \(method)")
        }
    }

    func initialize(_ params: JSONValue) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue ?? ""
        let version = MCPRouter.supportedVersions.contains(requested) ? requested : MCPRouter.latestVersion
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(Self.serverName), "version": .string(Self.serverVersion)],
            "instructions": "Waypoint 카드 보드. 사용법은 tracker 스킬을 따른다.",
        ]
    }

    func callTool(id: JSONValue, _ params: JSONValue) -> JSONValue {
        guard let name = params["name"]?.stringValue, MCPTools.definitions.contains(where: { $0.name == name }) else {
            return JSONRPC.error(id: id, code: JSONRPC.invalidParams, message: "Unknown tool")
        }
        let arguments = params["arguments"] ?? [:]
        guard arguments.objectValue != nil else {
            return JSONRPC.error(id: id, code: JSONRPC.invalidParams, message: "arguments must be an object")
        }
        let content: JSONValue
        let isError: Bool
        do {
            let value = try tools.call(name, arguments)
            try context.save()
            content = value
            isError = false
        } catch {
            context.rollback()
            let message = (error as? MCPToolError)?.message ?? String(describing: error)
            content = ["error": .string(message)]
            isError = true
        }
        return JSONRPC.result(id: id, [
            "content": [["type": "text", "text": .string(content.serializedString)]],
            "isError": .bool(isError),
        ])
    }
}
