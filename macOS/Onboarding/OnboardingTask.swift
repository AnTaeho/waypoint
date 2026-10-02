import Foundation
import Observation
import WaypointKit

/// 연결·해제 한 번: 도구마다 계획을 만들어 보이고, 확인하면 차례로 적용한다.
@MainActor @Observable
final class OnboardingTask {
    enum Phase: Equatable { case ready, applying, finished }

    /// 도구 하나의 상태
    struct Item {
        var plan: IntegrationPlan?
        var result: IntegrationInstaller.Result?
        /// 계획·적용을 멈춘 원인
        var error: String?

        var failures: [String] { result.map(OnboardingText.failures) ?? [] }
        var succeeded: Bool { result != nil && error == nil && failures.isEmpty }
        /// 다시 시도할 것이 있다
        var needsRetry: Bool { error != nil || !failures.isEmpty }
    }

    let providers: [AgentProvider]
    let action: IntegrationPlan.Action
    private(set) var items: [AgentProvider: Item] = [:]
    private(set) var phase: Phase = .ready
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let refreshed: () -> Void

    init(providers: [AgentProvider], action: IntegrationPlan.Action, home: URL, refreshed: @escaping () -> Void) {
        self.providers = providers
        self.action = action
        self.home = home
        self.refreshed = refreshed
        prepare()
    }

    /// 계획만 만든다(읽기만).
    func prepare() {
        phase = .ready
        items = [:]
        let context: IntegrationInstallContext
        do {
            guard let made = try IntegrationEnvironment.context() else {
                for provider in providers { items[provider] = Item(error: "앱 안의 연결 파일을 찾지 못함") }
                return
            }
            context = made
        } catch {
            for provider in providers { items[provider] = Item(error: OnboardingText.error(error, home: home.path)) }
            return
        }
        for provider in providers {
            do {
                items[provider] = Item(plan: try IntegrationInstaller.plan(provider, action, context: context))
            } catch {
                items[provider] = Item(error: OnboardingText.error(error, home: home.path))
            }
        }
    }

    /// 계획이 모두 비었다(이미 그 상태)
    var nothingToDo: Bool {
        items.values.allSatisfy { $0.error == nil && ($0.plan?.isEmpty ?? false) }
    }

    var canApply: Bool {
        phase == .ready && !nothingToDo && items.values.allSatisfy { $0.error == nil }
    }

    var needsRetry: Bool { phase == .finished && items.values.contains(where: \.needsRetry) }

    /// 확인한 계획을 차례로 적용한다. 명령 단계(`claude mcp`)가 최대 20초 걸려 메인 스레드 밖에서 돈다.
    func apply() async {
        guard canApply, let context = try? IntegrationEnvironment.context() else { return }
        phase = .applying
        for provider in providers {
            guard let plan = items[provider]?.plan, !plan.isEmpty else { continue }
            do {
                let result = try await Task.detached { try IntegrationInstaller.apply(plan, context: context) }.value
                items[provider]?.result = result
            } catch {
                items[provider]?.error = OnboardingText.error(error, home: home.path)
            }
        }
        phase = .finished
        refreshed()
    }

    /// 다시 계획하고 바로 적용한다(이미 확인한 일이다). 끝난 도구는 빈 계획이라 건너뛴다.
    func retry() async {
        prepare()
        if canApply { await apply() } else { phase = .finished; refreshed() }
    }

    /// 백업 폴더(쓴 파일이 있었던 도구만)
    var backupFolders: [URL] {
        providers.compactMap { items[$0]?.result?.backupFolder }
    }
}
