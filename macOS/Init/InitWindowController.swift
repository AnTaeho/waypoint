import AppKit
import SwiftData
import SwiftUI
import WaypointKit

/// 등록 확인 창. 메인 창과 따로 띄워 메인 창이 닫혀 있거나 메뉴 막대만 있어도 보이게 한다.
/// 초안이 여러 개면 맨 앞 것부터 하나씩. 창을 닫으면 지금 초안을 취소하고 다음 것을 보인다.
@MainActor
final class InitWindowController: NSObject, NSWindowDelegate {
    private let queue: ProjectDraftQueue
    private let container: ModelContainer
    private let registered: (Project) -> Void
    private var window: NSWindow?

    init(queue: ProjectDraftQueue, container: ModelContainer, registered: @escaping (Project) -> Void) {
        self.queue = queue
        self.container = container
        self.registered = registered
    }

    /// 초안이 들어오면 창을 띄우고 앞으로 가져온다.
    func show() {
        guard queue.current != nil else { return close() }
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        // 다른 앱이 앞에 있어 활성화가 미뤄져도 창은 보이게
        window.orderFrontRegardless()
    }

    func owns(_ other: NSWindow) -> Bool { other === window }

    private func makeWindow() -> NSWindow {
        let root = InitWindowRoot(
            queue: queue,
            cancel: { [weak self] in self?.cancelCurrent() },
            registered: { [weak self] draftID, project in self?.finish(draftID, project) }
        )
        .modelContainer(container)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "새 프로젝트 등록"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: Theme.Init.windowWidth, height: Theme.Init.windowHeight))
        return window
    }

    private func cancelCurrent() {
        if let id = queue.current?.id { queue.remove(id) }
        advance()
    }

    private func finish(_ draftID: UUID, _ project: Project) {
        queue.remove(draftID)
        advance()
        registered(project)
    }

    /// 남은 초안이 있으면 그대로 두고(내용이 바뀐다), 없으면 닫는다.
    private func advance() {
        if queue.current == nil { close() }
    }

    private func close() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// 닫기 단추: 지금 초안을 취소한다. 다음 초안이 있으면 창을 남긴다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id = queue.current?.id { queue.remove(id) }
        return queue.current == nil
    }
}

/// 큐의 맨 앞 초안을 보인다. 초안이 바뀌면(같은 폴더 교체 포함) 입력을 새로 채운다.
private struct InitWindowRoot: View {
    let queue: ProjectDraftQueue
    let cancel: () -> Void
    let registered: (UUID, Project) -> Void

    var body: some View {
        if let draft = queue.current {
            InitSheetView(draft: draft, cancel: cancel) { registered(draft.id, $0) }
                .id(draft.id)
        } else {
            Theme.surface
        }
    }
}
