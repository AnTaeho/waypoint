import Foundation
import WaypointKit

/// 첫 연결 지표(TRK-45, `OnboardingMetrics`). 기록은 `ReliabilityMonitor`가 `metrics.json`에 모아 쓴다.
/// 시도는 `startedAt`으로 가린다(지표 쪽이 같은 시각의 열린 시도만 고친다).
extension OnboardingModel {
    func recordStart() {
        let at = startedAt
        services?.reliability.update { $0.onboarding.start(at: at) }
    }

    func recordEnd(finished: Bool) {
        guard isPresented else { return }
        let attempt = startedAt
        services?.reliability.update {
            if finished { $0.onboarding.finish(at: Date(), attempt: attempt) } else { $0.onboarding.close(at: Date(), attempt: attempt) }
        }
    }

    /// 화면 판정이 바뀔 때마다(`OnboardingView`)
    func observe(_ progress: OnboardingProgress) {
        guard isPresented, progress.input.startedAt == startedAt else { return }
        let previous = lastBlocker
        lastBlocker = progress.blocker
        services?.reliability.update { $0.onboarding.observe(progress, previous: previous, at: Date()) }
    }

    /// 첫 기록 단계의 서버 「다시 시도」
    func retryServer() {
        let attempt = startedAt
        services?.reliability.update { $0.onboarding.retried(attempt: attempt) }
        services?.retryIntegration()
    }

    /// 설치 작업이 알리는 일을 지표로
    func reporter(_ stage: OnboardingMetrics.Stage) -> (OnboardingTask.Report) -> Void {
        let attempt = startedAt
        return { [weak self] report in
            self?.services?.reliability.update { metrics in
                switch report {
                case .applied(let provider): metrics.onboarding.installed(.init(provider), at: Date(), attempt: attempt)
                case .failed(let provider, let reason):
                    metrics.onboarding.fail(stage, reason, tool: .init(provider), at: Date(), attempt: attempt)
                case .retried: metrics.onboarding.retried(attempt: attempt)
                }
            }
        }
    }
}
