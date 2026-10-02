import AppKit
import Foundation
import SwiftData
import WaypointKit

extension AppServices {
    func receiveHook(_ input: HookInput, at: Date, replayed: Bool) {
        let id = input.sessionID
        let context = container.mainContext
        let session = try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first
        integration.receive(input.provider, sessionID: id, at: at, project: session?.project?.key, replayed: replayed)
        // 흡수(`replayed`)의 저장 실패는 `drainOutbox`가 알린다. 실시간 처리기의 표시는 흡수가 바꾸지 않는다.
        if !replayed, processor?.lastSaveFailed == true {
            integration.report("작업 기록 저장 실패")
            reliability.update { $0.failures.saveFailed += 1 }
        }
    }

    func receiveBinding(_ message: JSONValue, response: JSONValue?) {
        guard message["params"]?["name"] == "session_bind", response?["result"]?["isError"] == false,
              let id = message["params"]?["arguments"]?["sessionId"]?.stringValue else { return }
        let session = try? container.mainContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first
        if let project = session?.project { integration.bind(sessionID: id, project: project.key) }
    }

    /// 로컬 진단용 읽기 API. 입력 내용·세션 ID·설정 파일·경로를 반환하지 않는다.
    /// `metrics`는 숫자만 담은 신뢰성 지표(측정 스크립트 `scripts/measure-latency.py`가 읽는다).
    func integrationResponse() -> HTTPResponse {
        let data = (try? JSONEncoder().encode(integration.history)) ?? Data("{}".utf8)
        let history = JSONValue.parse(data) ?? [:]
        let metrics = (try? JSONEncoder().encode(reliability.metrics)).flatMap { JSONValue.parse($0) } ?? [:]
        return .text(JSONValue.object([
            "history": history,
            "metrics": metrics,
            "pending": .number(Double(integration.queue.count)),
            "queueUnreadable": .bool(integration.queue.unreadable)
        ]).serializedString)
    }

    /// 연결 설정을 연다(메뉴 막대·연동 상태 패널). 메인 창이 없으면 연다.
    func showOnboarding() {
        onboarding.present()
        if mainWindowCount == 0 { openMainWindow?() }
        NSApplication.shared.activate()
    }
}
