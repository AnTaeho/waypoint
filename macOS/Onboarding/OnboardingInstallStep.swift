import SwiftUI
import WaypointKit

/// 연결: 고른 도구의 계획을 보이고 확인하면 적용한다.
struct OnboardingInstallStep: View {
    let model: OnboardingModel
    let progress: OnboardingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if IntegrationEnvironment.installBlock == nil, let task = model.install {
                OnboardingTaskView(task: task, home: model.home)
            }
            if let blocker = progress.blocker, let text = OnboardingText.blocker(blocker) {
                Text(text).font(Theme.captionLarge).foregroundStyle(Theme.Onboarding.problem)
            }
        }
    }
}
