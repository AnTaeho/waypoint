import AppKit
import CoreData
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
    /// 서버 포트. 평소용 47821, 개발용 47822(`AppInstance`), 환경 변수 `WAYPOINT_PORT`가 먼저.
    let port = AppInstance.current.port()
    /// 방금 등록한 프로젝트. 메인 창이 받아서 사이드바에서 고르고 비운다.
    var pendingSelection: PersistentIdentifier?

    /// `project_init` 초안(메모리에만)
    @ObservationIgnored let drafts = ProjectDraftQueue()
    /// 메인 창 열기. 메인 창이 처음 뜰 때 `openWindow`를 넣어 둔다(창을 모두 닫은 뒤에도 쓰려고).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    /// 떠 있는 메인 창 수
    @ObservationIgnored var mainWindowCount = 0
    @ObservationIgnored private var initWindow: InitWindowController?

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var processor: HookProcessor?
    @ObservationIgnored private var server: LocalServer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var guides: GuideMonitor?
    @ObservationIgnored private var importObserver: NSObjectProtocol?

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

        let initWindow = InitWindowController(queue: drafts, container: container) { [weak self] project in
            self?.showRegistered(project)
        }
        self.initWindow = initWindow
        // 도구 응답이 창 생성을 기다리지 않게 다음 차례로 미룬다.
        drafts.onSubmit = { _ in
            Task { @MainActor in initWindow.show() }
        }
        let mcp = MCPServer(context: container.mainContext, drafts: drafts)
        let server = LocalServer(port: port) { request in
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

        observeCloudKitImports()

        // 첫 outbox 흡수 뒤 한 번, 그 뒤 60초마다
        refreshStates()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStates() }
        }
    }

    /// iPhone에서 온 변경(CloudKit 가져오기)을 메인 context에 들인다(`RemoteCardMerge`). 그대로 두면 iPhone에서
    /// 「다음 할 일로」 옮긴 카드가 Mac 화면에 아이디어로 남고, Mac이 그 카드를 저장하면 상태가 되돌아간다(2026-09-28 실측).
    private func observeCloudKitImports() {
        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
                event.type == .import, event.endDate != nil, event.succeeded
            else { return }
            MainActor.assumeIsolated { self?.refreshAfterImport() }
        }
    }

    /// 옮겨 온 카드가 active를 떠났으면 Mac 쪽 열린 연결도 바로 닫는다(연결은 `RemoteCardMerge`가 옮기지 않는다).
    private func refreshAfterImport() {
        let context = container.mainContext
        guard let merged = try? RemoteCardMerge.apply(from: ModelContext(container), to: context), merged > 0 else { return }
        CardLifecycle.closeStrayLinks(at: Date(), in: context)
        try? context.save()
    }

    /// 등록한 프로젝트를 메인 창 사이드바에서 고른다. 메인 창이 없으면 연다.
    private func showRegistered(_ project: Project) {
        pendingSelection = project.persistentModelID
        // 확인할 초안이 남았으면 등록 창을 앞에 둔다(선택은 메인 창이 뜰 때 받는다).
        if drafts.current != nil {
            initWindow?.show()
        } else if mainWindowCount == 0 {
            openMainWindow?()
        } else if let main = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && initWindow?.owns($0) != true
        }) {
            main.makeKeyAndOrderFront(nil)
        }
    }

    private func drainOutbox() {
        guard let processor, let directory = try? WaypointStore.supportDirectory() else { return }
        Outbox.drain(directory: directory) { processor.handle($0) }
    }

    /// `SessionEnd`가 오지 않은 세션을 끝내고(`SessionSweep`), active가 아닌 카드의 열린 연결을 닫고
    /// (`CardLifecycle.closeStrayLinks`), 남은 세션의 상태 캐시를 맞춘다.
    private func refreshStates() {
        let now = Date()
        processor?.sweep(now: now, probe: SessionSweep.systemProbe)
        let context = container.mainContext
        let closed = CardLifecycle.closeStrayLinks(at: now, in: context)
        let open = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.endedAt == nil })
        let sessions = (try? context.fetch(open)) ?? []
        if SessionStateCache.refresh(sessions, now: now) > 0 || closed > 0 {
            try? context.save()
        }
    }
}
