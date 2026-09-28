import Foundation
import Observation
import WaypointKit

/// 저장 폴더의 `usage.json`을 30초마다 확인해 바뀌었을 때만 다시 읽는다.
/// 파일은 중계 스크립트가 임시 파일 → mv로 바꿔 끼우므로 파일 감시(DispatchSource)는 교체 때마다 끊긴다.
/// 폴더 감시는 같은 폴더의 저장소·outbox 변화에도 깨어나서, 수정 시각만 보는 폴링이 가장 단순하다.
@MainActor
@Observable
final class UsageMonitor {
    private(set) var snapshot: UsageSnapshot?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastModified: Date?
    @ObservationIgnored private let url: URL?

    static let pollInterval: TimeInterval = 30

    init() {
        url = (try? WaypointStore.supportDirectory(create: false))?.appendingPathComponent(UsageSnapshot.fileName)
    }

    /// 한 번 바로 읽고 30초마다 다시 확인한다. 두 번 불러도 타이머는 하나.
    func start() {
        guard timer == nil else { return }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func reload() {
        guard let url else { return }
        // URL.resourceValues는 값을 캐시하므로 매번 파일 속성을 새로 읽는다.
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else {
            // 파일이 사라지면 게이지도 숨긴다.
            lastModified = nil
            if snapshot != nil { snapshot = nil }
            return
        }
        guard modified != lastModified else { return }
        lastModified = modified
        let next = UsageSnapshot.load(from: url)
        if next != snapshot { snapshot = next }
    }
}
