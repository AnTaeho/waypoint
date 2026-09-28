import Foundation
import SwiftData
import WaypointKit

/// 등록된 지침 문서의 로컬 변경을 따라간다. 문서들의 부모 폴더를 FSEvents로 감시하고,
/// 이벤트가 오면(0.4초 디바운스) 모든 문서를 해시로 다시 확인한다. 감시 폴더가 바뀔 때(등록·해제)와 시작할 때도 전부 확인한다.
@MainActor
final class GuideMonitor {
    private let context: ModelContext
    private var watcher: GuideWatcher?
    private var directories: Set<String> = []
    private var saveObserver: NSObjectProtocol?

    init(context: ModelContext) {
        self.context = context
    }

    func start() {
        guard watcher == nil else { return }
        watcher = GuideWatcher { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
        reload(force: true)
        // 문서 등록·해제는 저장으로 드러난다. 폴더 목록이 달라졌을 때만 감시를 다시 건다.
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(force: false) }
        }
    }

    private func reload(force: Bool) {
        let docs = (try? context.fetch(FetchDescriptor<GuideDoc>())) ?? []
        let dirs = Set(docs.compactMap { GuideLibrary.fileURL(of: $0)?.deletingLastPathComponent().path })
        guard force || dirs != directories else { return }
        directories = dirs
        watcher?.watch(dirs)
        checkAll()
    }

    private func checkAll() {
        GuideLibrary.checkAll(at: Date(), context: context)
    }
}
