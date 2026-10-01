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
    /// - Parameter contextID: `handle` 뒤에 부른다. 대기로 둔 블록의 응답 ID(없으면 nil). 본문이 있는 200 응답에만 머리로 싣는다.
    public static func respond(to request: HTTPRequest, handle: (AgentProvider, String, Data, Int?) -> String?,
                               contextID: () -> String? = { nil }) -> HTTPResponse {
        guard let event = eventName(from: request.path) else { return .notFound }
        guard request.method == "POST" else { return .methodNotAllowed }
        let provider = provider(from: request.path)
        let pid = provider == .claude ? claudePid(from: request) : HookParsing.pid(request.headers[processPidHeader])
        let context = handle(provider, event, request.body, pid)
        guard contextEvents.contains(event) || lateContextEvents.contains(event) && !(context ?? "").isEmpty
        else { return .noContent }
        let text = context ?? ""
        guard !text.isEmpty, let id = contextID(), isContextID(id) else { return .text(text) }
        return HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: Data(text.utf8),
                            headers: [contextIDHeader: id])
    }

    // MARK: - 수신 확인 (TRK-35)

    /// 블록을 stdout에 출력한 스크립트가 응답 ID를 돌려보내는 곳. Claude·Codex 공용(ID가 세션을 가리킨다).
    public static let ackPath = "/hooks/ack"
    /// 요청 머리: 이 스크립트는 출력 뒤 확인을 보낸다(`1`). 없으면 옛 스크립트로 보고 블록을 바로 확정한다.
    public static let contextAckHeader = "x-waypoint-context-ack"
    /// 응답 머리: 대기로 둔 블록의 ID
    public static let contextIDHeader = "X-Waypoint-Context-ID"

    public static func acknowledges(_ request: HTTPRequest) -> Bool {
        request.headers[contextAckHeader] == "1"
    }

    /// 응답 ID 꼴(소문자 UUID). 스크립트도 같은 꼴만 돌려보낸다.
    public static func isContextID(_ id: String) -> Bool {
        id.count == 36 && id.allSatisfy { $0 == "-" || $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }
    }

    /// `POST /hooks/ack` 본문 `{"contextId":"<ID>"}`. 모르는 ID도 `204`(스크립트는 결과를 보지 않는다), 꼴이 틀리면 `400`.
    public static func respondAck(to request: HTTPRequest, acknowledge: (String) -> Void) -> HTTPResponse {
        guard request.method == "POST" else { return .methodNotAllowed }
        guard let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let id = object["contextId"] as? String, isContextID(id)
        else { return .badRequest }
        acknowledge(id)
        return .noContent
    }
}
