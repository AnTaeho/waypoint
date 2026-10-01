import Foundation
import Observation
import SwiftData
import WaypointKit

/// 지침·기억 출처 목록을 들고 있다가 파일이 바뀌면 다시 모은다. 모은 결과는 메모리에만 둔다.
///
/// 감시는 `GuidanceWatchPlan`의 폴더(홈 자체는 빼고)를 FSEvents로 보고, 출처와 상관없는 경로(대화 기록·로그)는
/// 디바운스 전에 거른다. 등록 프로젝트가 바뀌면(저장 알림) 다시 모으고, 앱이 앞으로 오거나 화면을 열 때도 다시 모은다
/// (홈 바로 아래 파일은 감시하지 않으므로).
@MainActor
@Observable
final class GuidanceMonitor {
    private(set) var snapshot: GuidanceSnapshot = .empty
    private(set) var loaded = false

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let collector = GuidanceCollector.current()
    @ObservationIgnored private var watcher: GuideWatcher?
    @ObservationIgnored private var projects: [GuidanceProject] = []
    @ObservationIgnored private var roots: Set<String> = []
    @ObservationIgnored private var saveObserver: NSObjectProtocol?
    @ObservationIgnored private var collecting = false
    @ObservationIgnored private var again = false

    init(context: ModelContext) {
        self.context = context
    }

    func start() {
        guard watcher == nil else { return }
        // 거르는 규칙은 등록 프로젝트와 상관없다(`~/.claude/projects` 위치만 쓴다).
        let filter = GuidanceWatchPlan(collector: collector, projects: [], ancestors: [])
        watcher = GuideWatcher(debounce: 0.5, accept: { filter.accepts($0) }) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        projects = currentProjects()
        refresh()
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.projectsMayHaveChanged() }
        }
    }

    /// 지금 디스크 상태로 다시 모은다. 모으는 중이면 끝난 뒤 한 번 더.
    func refresh() {
        guard !collecting else {
            again = true
            return
        }
        collecting = true
        let collector = collector
        let projects = projects
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = collector.collect(projects: projects)
            let plan = GuidanceWatchPlan(collector: collector, projects: projects, ancestors: snapshot.ancestors)
            await self?.apply(snapshot, roots: plan.roots)
        }
    }

    private func apply(_ new: GuidanceSnapshot, roots newRoots: Set<String>) {
        if new != snapshot { snapshot = new }
        loaded = true
        if newRoots != roots {
            roots = newRoots
            watcher?.watch(newRoots)
        }
        collecting = false
        if again {
            again = false
            refresh()
        }
    }

    private func projectsMayHaveChanged() {
        let current = currentProjects()
        guard current != projects else { return }
        projects = current
        refresh()
    }

    private func currentProjects() -> [GuidanceProject] {
        let all = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.key)]))) ?? []
        return all.map { GuidanceProject(key: $0.key, rootPath: $0.rootPath) }
    }
}
