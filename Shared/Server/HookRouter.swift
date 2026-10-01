import Foundation

/// `POST /hooks/<EventName>` 라우팅. 소켓 없이 테스트할 수 있게 요청 → 응답만 다룬다.
public enum HookRouter {
    public static let prefix = "/hooks/"
    public static let codexPrefix = "/hooks/codex/"

    /// 컨텍스트 본문을 늘 돌려주는 이벤트(`200 text/plain`, 빈 본문일 수 있다).
    public static let contextEvents: Set<String> = ["SessionStart"]
    /// 주입할 것이 있을 때만 `200 text/plain`, 없으면 `204`인 이벤트(늦은 주입, SPEC 5장).
    public static let lateContextEvents: Set<String> = ["UserPromptSubmit"]

    /// 경로에서 이벤트 이름을 꺼낸다. 영문자·숫자만 허용.
    public static func eventName(from path: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let length = path.hasPrefix(codexPrefix) ? codexPrefix.count : prefix.count
        let name = String(path.dropFirst(length))
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return name
    }

    /// 훅 스크립트가 Claude Code 프로세스 PID를 싣는 머리(SPEC 6장). 파서가 이름을 소문자로 바꾼다.
    public static let claudePidHeader = "x-waypoint-claude-pid"
    public static let processPidHeader = "x-waypoint-process-pid"

    public static func provider(from path: String) -> AgentProvider {
        path.hasPrefix(codexPrefix) ? .codex : .claude
    }

    /// 머리의 Claude Code PID. 없거나 숫자가 아니면 nil.
    public static func claudePid(from request: HTTPRequest) -> Int? {
        HookParsing.pid(request.headers[claudePidHeader])
    }

    /// - Parameter handle: (도구, 이벤트 이름, 원본 JSON, 도구 프로세스 PID) → 주입할 텍스트(없으면 nil)
    public static func respond(to request: HTTPRequest, handle: (AgentProvider, String, Data, Int?) -> String?) -> HTTPResponse {
        guard let event = eventName(from: request.path) else { return .notFound }
        guard request.method == "POST" else { return .methodNotAllowed }
        let provider = provider(from: request.path)
        let pid = provider == .claude ? claudePid(from: request) : HookParsing.pid(request.headers[processPidHeader])
        let context = handle(provider, event, request.body, pid)
        if contextEvents.contains(event) {
            return .text(context ?? "")
        }
        if lateContextEvents.contains(event), let context, !context.isEmpty {
            return .text(context)
        }
        return .noContent
    }
}
