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

    // MARK: - 원격 replay (TRK-53)

    /// 원격·컨테이너 훅이 앱에 닿지 못해 쌓아 둔 outbox 줄(JSON Lines)을 다시 보내는 곳.
    public static let replayPath = "/hooks/replay"

    /// 흡수가 남은 동안 처리하지 않고 outbox 뒤에 세울 수 있는 이벤트(응답 본문이 필요 없는 것).
    public static func defersWhileDraining(_ event: String) -> Bool {
        !contextEvents.contains(event) && !lateContextEvents.contains(event)
    }

    /// `POST /hooks/replay`. 줄을 이 Mac의 outbox에 붙인 뒤에만 `200 {"accepted":n,"rejected":m}`(원격은 200을 받아야 줄을 지운다).
    /// 줄이 상한(`Outbox.replayLineLimit`)을 넘거나 읽을 수 있는 줄이 하나도 없으면 `400`, 붙이지 못하면 `500`.
    public static func respondReplay(to request: HTTPRequest, append: (Data) throws -> Outbox.AppendResult) -> HTTPResponse {
        guard request.method == "POST" else { return .methodNotAllowed }
        let lines = request.body.split(separator: UInt8(ascii: "\n")).count
        guard lines > 0, lines <= Outbox.replayLineLimit else { return .badRequest }
        let result: Outbox.AppendResult
        do {
            result = try append(request.body)
        } catch {
            return HTTPResponse(status: 500, contentType: "text/plain; charset=utf-8", body: Data())
        }
        guard result.accepted > 0 else { return .badRequest }
        return HTTPResponse(status: 200, contentType: "application/json",
                            body: Data("{\"accepted\":\(result.accepted),\"rejected\":\(result.rejected)}".utf8))
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
