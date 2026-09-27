import Foundation
import Observation
import SwiftData
import WaypointKit

/// 창과 상관없이 앱이 살아 있는 동안 도는 것: outbox 흡수, 로컬 서버, 세션 상태 캐시 갱신 타이머.
/// 메뉴 막대 상주(`MenuBarExtra`)라 창을 닫아도 계속 돈다.
@MainActor
@Observable
final class AppServices {
    private(set) var serverState: LocalServer.State = .stopped

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var processor: HookProcessor?
    @ObservationIgnored private var server: LocalServer?
    @ObservationIgnored private var timer: Timer?

    /// 멈춤 판정 캐시를 맞추는 주기(초). 화면 판정은 `TimelineView`가 따로 다시 계산한다.
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

        let server = LocalServer { request in
            HookRouter.respond(to: request) { event, body in
                processor.handle(event: event, json: body, at: Date())
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

        refreshStates()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStates() }
        }
    }

    private func drainOutbox() {
        guard let processor, let directory = try? WaypointStore.supportDirectory() else { return }
        Outbox.drain(directory: directory) { processor.handle($0) }
    }

    private func refreshStates() {
        let context = container.mainContext
        let open = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.endedAt == nil })
        let sessions = (try? context.fetch(open)) ?? []
        if SessionStateCache.refresh(sessions, now: Date()) > 0 {
            try? context.save()
        }
    }
}
