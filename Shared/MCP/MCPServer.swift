import Foundation
import SwiftData

/// JSON-RPC 메서드 처리: `initialize`, `ping`, `tools/list`, `tools/call`(SPEC 7장).
/// 넘겨받은 context가 속한 액터(앱에서는 메인 액터)에서만 부른다. Sendable이 아니다.
public final class MCPServer {
    public let tools: MCPTools
    public static let serverName = "waypoint"
    public static let serverVersion = "0.7.0"
    /// 도구 호출 뒤 저장. 테스트가 저장 실패를 흉내 낼 때 바꾼다.
    var saveContext: (ModelContext) throws -> Void = { try $0.save() }
    /// 미룬 도구의 바깥 호출을 돌리는 곳. 테스트에서 바꾼다.
    public var background: (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) }
    /// 미룬 도구가 끝난 뒤 돌아오는 곳(context의 액터 = 앱에서는 메인 큐). 테스트에서 바꾼다.
    public var resume: @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }

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

    /// 오래 걸리는 도구(GitHub) 호출이면 맡고 true. 호출은 `background`에서 돌고, 끝나면 `resume`(context의 액터)에서
    /// 기록한 뒤 `completion`을 부른다. 그사이 다른 요청은 평소대로 처리된다. 맡지 않으면 false(`handle`로 보낸다).
    public func handleDeferred(_ message: JSONValue, completion: @escaping (JSONValue) -> Void) -> Bool {
        guard message["jsonrpc"] == "2.0", message["method"] == "tools/call", let id = message["id"],
              id.stringValue != nil || id.numberValue != nil,
              let name = message["params"]?["name"]?.stringValue, MCPTools.deferredTools.contains(name),
              let arguments = message["params"]?["arguments"], arguments.objectValue != nil
        else { return false }
        let plan: MCPTools.GitHubPlan
        do {
            plan = try tools.githubPlan(name, arguments)
        } catch {
            completion(Self.toolReply(id: id, .failure(error)))
            return true
        }
        let finish = UncheckedSendable { [self] (result: Result<GitHubCreated, GitHubError>) in
            completion(Self.toolReply(id: id, Result {
                let created = try result.mapError { MCPToolError($0) }.get()
                return try ContextReload.commit(context, save: saveContext) { try tools.githubFinish(plan, created) }
            }))
        }
        let cli = tools.github, resume = resume
        background {
            let result = plan.job.run(cli)
            resume { finish.value(result) }
        }
        return true
    }

    static func toolReply(id: JSONValue, _ result: Result<JSONValue, Error>) -> JSONValue {
        let content: JSONValue
        var isError = false
        switch result {
        case .success(let value): content = value
        case .failure(let error):
            content = ["error": .string((error as? MCPToolError)?.message ?? String(describing: error))]
            isError = true
        }
        return JSONRPC.result(id: id, [
            "content": [["type": "text", "text": .string(content.serializedString)]],
            "isError": .bool(isError),
        ])
    }

    func initialize(_ params: JSONValue) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue ?? ""
        let version = MCPRouter.supportedVersions.contains(requested) ? requested : MCPRouter.latestVersion
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(Self.serverName), "version": .string(Self.serverVersion)],
            "instructions": "Waypoint 카드 보드(Claude Code·Codex). tracker 스킬을 따른다. 작업 대상 폴더를 project_resolve로 확인하고 session_bind로 연결한다. 실제 sessionId는 훅 블록 또는 Codex 실행 환경 CODEX_SESSION_ID/CODEX_THREAD_ID에서 얻는다. ID를 추측하거나 만들지 않는다. 연결 결과의 sessionId를 card_start·card_create에 쓴다. Codex ID의 codex: 접두사를 유지한다. 작업 시작·전환에는 card_start, 나중에 할 일은 card_create(kind: idea), 중단·마무리는 card_handoff. 완료는 사용자 승인 후에만 card_update(status: done). Codex의 project_init 및 세션 없는 card_create에는 provider: codex를 보낸다.",
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
        // 도구가 바꾸다 실패하거나 저장에 실패하면 rollback 뒤 저장소 값으로 다시 읽는다(`ContextReload.commit`).
        return Self.toolReply(id: id, Result {
            try ContextReload.commit(context, save: saveContext) { try tools.call(name, arguments) }
        })
    }
}
