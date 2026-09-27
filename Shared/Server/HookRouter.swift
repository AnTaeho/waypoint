import Foundation

/// `POST /hooks/<EventName>` 라우팅. 소켓 없이 테스트할 수 있게 요청 → 응답만 다룬다.
public enum HookRouter {
    public static let prefix = "/hooks/"

    /// 컨텍스트 본문을 돌려주는 이벤트(`200 text/plain`). 나머지는 `204`.
    public static let contextEvents: Set<String> = ["SessionStart"]

    /// 경로에서 이벤트 이름을 꺼낸다. 영문자·숫자만 허용.
    public static func eventName(from path: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let name = String(path.dropFirst(prefix.count))
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return name
    }

    /// - Parameter handle: (이벤트 이름, 본문 JSON) → 컨텍스트 이벤트면 주입할 텍스트(없으면 nil)
    public static func respond(to request: HTTPRequest, handle: (String, Data) -> String?) -> HTTPResponse {
        guard let event = eventName(from: request.path) else { return .notFound }
        guard request.method == "POST" else { return .methodNotAllowed }
        let context = handle(event, request.body)
        if contextEvents.contains(event) {
            return .text(context ?? "")
        }
        return .noContent
    }
}
