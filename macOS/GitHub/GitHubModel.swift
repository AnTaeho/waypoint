import Foundation
import Observation
import SwiftData
import WaypointKit

/// 이슈·PR 열기와 마지막으로 확인한 상태. 상태는 이 Mac의 파일에만 둔다.
@MainActor
@Observable
final class GitHubModel {
    private(set) var cache: GitHubStatusCache
    @ObservationIgnored private let directory = try? WaypointStore.supportDirectory()
    @ObservationIgnored private let cli = GitHubCLI.system()
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var lastFailure: Date?
    /// 확인에 실패한 뒤 다시 해 보기까지 두는 간격
    private static let retryAfter: TimeInterval = 60

    init() {
        cache = directory.map { GitHubStatusCache.load(directory: $0) } ?? GitHubStatusCache()
    }

    /// 확인한 상태를 입힌 목록
    func shown(_ items: [GitHubItem]) -> [GitHubItem] { cache.applied(to: items) }

    /// 오래된 것이 있으면 뒤에서 한 번에 다시 읽는다. 카드 상태는 건드리지 않는다.
    func refreshIfStale(_ items: [GitHubItem], now: Date = Date()) {
        guard !refreshing, !cache.stale(items, now: now).isEmpty,
              lastFailure.map({ now.timeIntervalSince($0) >= Self.retryAfter }) ?? true else { return }
        refreshing = true
        let cli = cli
        Task {
            let result = await Task.detached { GitHubStatusQuery.refresh(items, cli: cli) }.value
            refreshing = false
            switch result {
            case .success(let fresh):
                lastFailure = nil
                cache.merge(fresh)
                if let directory { try? cache.save(directory: directory) }
            case .failure:
                lastFailure = Date()
            }
        }
    }

    /// 연 뒤 기록까지 남긴다. 실패하면 원인을 돌려준다.
    func open(_ draft: GitHubDraft, card: Card, in context: ModelContext) async -> GitHubError? {
        guard let project = card.project else { return .noRemote }
        let job: GitHubJob
        do {
            job = try GitHubPlanner.job(draft, rootPath: project.rootPath)
        } catch {
            return error as? GitHubError ?? .failed(String(describing: error))
        }
        let cli = cli
        switch await Task.detached(operation: { job.run(cli) }).value {
        case .success(let created):
            GitHubLog.record(created, project: project, card: card, session: nil, at: Date(), in: context)
            try? context.save()
            return nil
        case .failure(let error):
            return error
        }
    }
}
