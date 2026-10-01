import Foundation
import SwiftData
import WaypointKit

extension AppServices {
    func receiveHook(_ input: HookInput, at: Date, replayed: Bool) {
        let id = input.sessionID
        let context = container.mainContext
        let session = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first
        integration.receive(input.provider, sessionID: id, at: at, project: session?.project?.key, replayed: replayed)
        if processor?.lastSaveFailed == true {
            integration.report("훅은 받았지만 작업 기록을 저장하지 못했습니다. 저장 공간과 권한을 확인하세요.")
        }
    }

    func receiveBinding(_ message: JSONValue, response: JSONValue?) {
        guard message["params"]?["name"] == "session_bind", response?["result"]?["isError"] == false,
              let id = message["params"]?["arguments"]?["sessionId"]?.stringValue else { return }
        let session = try? container.mainContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first
        if let project = session?.project { integration.bind(sessionID: id, project: project.key) }
    }

    /// 로컬 진단용 읽기 API. 입력 내용·세션 ID·설정 파일·경로를 반환하지 않는다.
    func integrationResponse() -> HTTPResponse {
        let data = (try? JSONEncoder().encode(integration.history)) ?? Data("{}".utf8)
        let history = JSONValue.parse(data) ?? [:]
        return .text(JSONValue.object([
            "history": history,
            "pending": .number(Double(integration.queue.count)),
            "queueUnreadable": .bool(integration.queue.unreadable)
        ]).serializedString)
    }
}
