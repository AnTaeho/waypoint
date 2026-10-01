#if os(macOS)
import CoreServices
import Foundation

/// 폴더 여러 개를 FSEvents(파일 단위 이벤트)로 감시하고, 이벤트가 멎은 뒤 `debounce`초가 지나면
/// 바뀐 폴더 목록을 한 번에 넘긴다. 콜백은 자체 직렬 큐에서 부른다(받는 쪽이 메인으로 옮긴다).
///
/// 경로는 정확히 맞추지 않는다(`/tmp`↔`/private/tmp`, 원자적 교체의 임시 파일 이름). 이벤트가 난 파일의
/// 부모 폴더를 넘기므로, 받는 쪽은 그 폴더에 있는 문서를 모두 다시 확인한다.
public final class GuideWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (_ directories: Set<String>) -> Void
    /// 이벤트가 난 경로 중 받을 것. 거른 경로는 디바운스를 다시 걸지 않는다(쉬지 않고 쓰이는 파일이 넘기기를 미루지 않게).
    public typealias Filter = @Sendable (_ path: String) -> Bool

    private let queue = DispatchQueue(label: "dev.antaeho.waypoint.guide-watcher")
    private let debounce: TimeInterval
    private let handler: Handler
    private let accept: Filter
    // 아래 상태는 `queue`에서만 만진다.
    private var stream: FSEventStreamRef?
    private var pending: Set<String> = []
    private var flush: DispatchWorkItem?

    public init(debounce: TimeInterval = 0.4, accept: @escaping Filter = { _ in true }, handler: @escaping Handler) {
        self.debounce = debounce
        self.accept = accept
        self.handler = handler
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// 감시할 폴더를 바꾼다(빈 목록이면 멈춘다). 바로 돌아온다.
    public func watch(_ directories: Set<String>) {
        queue.async { self.restart(directories) }
    }

    /// 테스트·종료용: 감시를 멈추고 끝날 때까지 기다린다.
    public func stop() {
        queue.sync { self.restart([]) }
    }

    private func restart(_ directories: Set<String>) {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        guard !directories.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, GuideWatcher.callback, &context,
            Array(directories) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<GuideWatcher>.fromOpaque(info).takeUnretainedValue()
        let list = unsafeBitCast(paths, to: NSArray.self)
        var dirs: Set<String> = []
        for case let path as String in list.prefix(count) where watcher.accept(path) {
            dirs.insert((path as NSString).deletingLastPathComponent)
        }
        guard !dirs.isEmpty else { return }
        watcher.received(dirs)
    }

    /// `queue`에서 불린다.
    private func received(_ dirs: Set<String>) {
        pending.formUnion(dirs)
        flush?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.pending.isEmpty else { return }
            let batch = self.pending
            self.pending = []
            self.handler(batch)
        }
        flush = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
#endif
