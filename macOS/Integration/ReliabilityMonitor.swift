import Foundation
import Observation
import SwiftData
import WaypointKit

/// 기록 신뢰성 지표(`ReliabilityMetrics`)와 재개 시간 대기 목록. 지표는 저장 폴더 `metrics.json`(0600)에만 둔다.
/// 파일은 훅마다 쓰지 않고 10초 점검 때 바뀐 것이 있으면 쓴다(`saveIfNeeded`).
@MainActor @Observable
final class ReliabilityMonitor {
    private(set) var metrics: ReliabilityMetrics
    @ObservationIgnored private var resumes = ResumeTracker()
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private let url: URL?

    static let fileName = "metrics.json"

    init(directory: URL? = try? WaypointStore.supportDirectory()) {
        url = directory?.appendingPathComponent(Self.fileName)
        if let url, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(ReliabilityMetrics.self, from: data) {
            metrics = stored
        } else {
            metrics = ReliabilityMetrics()
        }
    }

    func update(_ change: (inout ReliabilityMetrics) -> Void) {
        change(&metrics)
        dirty = true
    }

    /// 실시간 훅 한 건: 저장까지 잰 뒤, 데이터 변경 알림을 낸 다음 메인 큐가 한 번 돈 시각을 화면 반영으로 본다.
    func receipt(receivedAt: Date, savedAt: Date) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.update { $0.recordReceipt(receivedAt: receivedAt, savedAt: savedAt, shownAt: Date()) }
            }
        }
    }

    func copied(_ attempt: CardResumeAttempt) { resumes.copied(attempt) }

    /// 재개 대기 카드가 새 세션과 연결됐는지 본다. 연결은 MCP(`card_start`)로 생기므로 요청마다·10초 점검마다 부른다.
    func checkResumes(in context: ModelContext, now: Date = Date()) {
        guard !resumes.isEmpty else { return }
        let ids = resumes.cardIDs
        let cards = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let durations = resumes.check(cards, now: now)
        guard !durations.isEmpty else { return }
        update { metrics in durations.forEach { metrics.recordResume(seconds: $0) } }
    }

    func saveIfNeeded() {
        guard dirty, let url, let data = try? JSONEncoder().encode(metrics) else { return }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            dirty = false
        } catch {}
    }
}
