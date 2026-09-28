import Foundation
import Observation
import SwiftData
import WaypointKit

/// 창과 상관없이 앱이 살아 있는 동안 도는 것: outbox 흡수, 로컬 서버(훅·MCP), 세션 정리·상태 캐시 갱신 타이머, 지침 문서 감시.
/// 메뉴 막대 상주(`MenuBarExtra`)라 창을 닫아도 계속 돈다.
@MainActor
@Observable
final class AppServices {
    private(set) var serverState: LocalServer.State = .stopped

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var processor: HookProcessor?
    @ObservationIgnored private var server: LocalServer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var guides: GuideMonitor?

    /// `SessionEnd` 없이 끝난 세션 정리와 멈춤 판정 캐시를 맞추는 주기(초). 화면 판정은 `TimelineView`가 따로 다시 계산한다.
    static let refreshInterval: TimeInterval = 60

    init(container: ModelContainer) {
        self.container = container
    }

    /// outbox를 먼저 흡수하고 서버를 연다. 두 번 불러도 한 번만 연다.
    func start() {
        guard server == nil else { return }
        let processor = HookProcessor(context: container.mainContext)
        self.processor = processor
        drainOutbox()

        let mcp = MCPServer(context: container.mainContext)
        let server = LocalServer { request in
            if MCPRouter.matches(request.path) {
                return MCPRouter.respond(to: request) { mcp.handle($0) }
            }
            return HookRouter.respond(to: request) { event, body, claudePid in
                processor.handle(event: event, json: body, at: Date(), claudePid: claudePid)
            }
        }
        server.onStateChange = { [weak self] state in
            guard let self else { return }
            self.serverState = state
            // 흡수와 서버가 열리는 사이에 스크립트가 outbox로 보낸 것까지 받는다.
            if state == .ready { self.drainOutbox() }
        }
        self.server = server
        server.start()

        // 지침 문서: 시작할 때 모두 확인하고 로컬 변경을 감시한다.
        let guides = GuideMonitor(context: container.mainContext)
        self.guides = guides
        guides.start()

        // 첫 outbox 흡수 뒤 한 번, 그 뒤 60초마다
        refreshStates()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStates() }
        }
    }

    private func drainOutbox() {
        guard let processor, let directory = try? WaypointStore.supportDirectory() else { return }
        Outbox.drain(directory: directory) { processor.handle($0) }
    }

    /// `SessionEnd`가 오지 않은 세션을 끝내고(`SessionSweep`), 남은 세션의 상태 캐시를 맞춘다.
    private func refreshStates() {
        let now = Date()
        processor?.sweep(now: now, probe: SessionSweep.systemProbe)
        let context = container.mainContext
        let open = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.endedAt == nil })
        let sessions = (try? context.fetch(open)) ?? []
        if SessionStateCache.refresh(sessions, now: now) > 0 {
            try? context.save()
        }
    }
}
