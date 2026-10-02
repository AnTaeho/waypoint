import SwiftUI
import WaypointKit

/// 도구 고르기. 이미 연결된 도구는 그 자리에서 다시 설치·연결 해제할 수 있다.
struct OnboardingToolsStep: View {
    let services: AppServices
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(AgentProvider.allCases, id: \.self) { provider in
                row(provider)
            }
            if let reason = IntegrationEnvironment.installBlock {
                Text(reason).font(Theme.captionLarge).foregroundStyle(Theme.Onboarding.muted)
            }
        }
    }

    private func row(_ provider: AgentProvider) -> some View {
        let installation = services.integration.installations[provider]
        let state = installation?.state ?? .missing
        let task = model.toolTask.flatMap { $0.providers == [provider] ? $0 : nil }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Toggle(isOn: selection(provider)) {
                    Text(provider.name).font(Theme.bodyMedium).foregroundStyle(Theme.text)
                }
                .toggleStyle(.checkbox)
                Text(OnboardingText.installation(installation))
                    .font(Theme.captionLarge)
                    .foregroundStyle(state == .attention ? Theme.Onboarding.problem
                                     : state == .ready ? Theme.Onboarding.ok : Theme.Onboarding.muted)
                Spacer()
                if state != .missing, task == nil {
                    Group {
                        Button("다시 설치") { model.startToolTask(provider, .install) }
                        Button("연결 해제") { model.startToolTask(provider, .remove) }
                    }
                    .font(Theme.captionLarge)
                    .disabled(IntegrationEnvironment.installBlock != nil)
                }
            }
            if let task {
                OnboardingTaskView(task: task, home: model.home, done: { model.clearToolTask() })
            }
        }
        .padding(Theme.Onboarding.boxPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Onboarding.boxRadius))
    }

    private func selection(_ provider: AgentProvider) -> Binding<Bool> {
        Binding {
            model.selected.contains(provider)
        } set: { on in
            if on { model.selected.insert(provider) } else { model.selected.remove(provider) }
        }
    }

}
