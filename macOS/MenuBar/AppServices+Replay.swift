import Foundation
import WaypointKit

/// 원격·컨테이너 훅의 replay(TRK-53, SPEC 「원격·컨테이너 수집」). 받은 줄은 저장 폴더의 `replay/`에 붙이고 바로 답한 뒤
/// 메인 큐 한 차례에 `RemoteReplay.budget`만큼씩 처리한다. 그사이 온 실시간 훅이 먼저 처리돼 로컬 훅이 1초 안에 답을 받는다.
extension AppServices {
    var replayDirectory: URL? {
        (try? WaypointStore.supportDirectory()).map { RemoteReplay.directory(support: $0) }
    }

    /// `POST /hooks/replay`: 붙인 뒤에만 200(원격은 200을 받아야 줄을 지운다).
    func receiveReplay(_ request: HTTPRequest) -> HTTPResponse {
        guard let directory = replayDirectory else { return HTTPResponse(status: 500) }
        let response = HookRouter.respondReplay(to: request) { try Outbox.append($0, directory: directory) }
        if response.status == 200 { scheduleReplay() }
        return response
    }

    /// replay 줄이 남은 동안 블록이 필요 없는 실시간 훅은 처리하지 않고 그 뒤에 세운다. 먼저 처리하면 늦게 들어오는
    /// 그 세션의 이른 기록이 「끝난 세션의 지난 기록」으로 버려질 수 있다. 세웠으면 true(응답 204).
    func deferBehindReplay(event: String, provider: AgentProvider, body: Data, pid: Int?, receivedAt: Date) -> Bool {
        guard replayBacklog, HookRouter.defersWhileDraining(event), let directory = replayDirectory,
              let line = Outbox.line(event: event, provider: provider, receivedAt: receivedAt, pid: pid, payload: body),
              (try? Outbox.append(line, directory: directory)) != nil
        else { return false }
        scheduleReplay()
        return true
    }

    /// 다음 메인 큐 차례에 replay를 이어 간다. 이미 예약돼 있으면 하나만.
    func scheduleReplay() {
        replayBacklog = true
        guard !replayScheduled else { return }
        replayScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.replayScheduled = false
                self?.drainReplay()
            }
        }
    }

    /// 한 차례 처리. 남았으면 다음 차례를 예약한다. 저장에 실패하면 그 줄부터 남기고 10초 점검에서 다시 한다
    /// (그동안에도 뒤에 세우기는 계속한다 — 순서를 지키려고).
    func drainReplay() {
        guard let processor, let directory = replayDirectory else { return }
        let result = RemoteReplay.drain(directory: directory, processor: processor,
                                        deadline: Date().addingTimeInterval(RemoteReplay.budget)) { entry in
            if let input = HookInput(event: entry.event, json: entry.payload, provider: entry.provider) {
                receiveHook(input, at: entry.receivedAt, replayed: true)
            }
        }
        if result.processed > 0 || result.skipped > 0 || result.retryPending { reliability.update { $0.recordAbsorb(result) } }
        if result.skipped > 0 { integration.report("누락 기록 \(result.skipped)건 형식 오류") }
        if result.retryPending { integration.report("작업 기록 저장 실패 · 미처리 기록 보존") }
        // 화면 갱신은 2초에 한 번과 끝날 때만(조각마다 대시보드를 다시 그리면 처리가 느려진다)
        if result.processed > 0, !result.more || Date().timeIntervalSince(lastDataChange) >= 2 { markDataChanged() }
        replayBacklog = result.more || result.retryPending
        if result.more { scheduleReplay() }
    }
}
