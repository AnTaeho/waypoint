import SwiftUI
import WaypointKit

/// 첫 기록: 고른 도구마다 시작 이후의 기록을 기다리고, 프로젝트에 연결된 기록이 오면 끝 화면이 된다.
struct OnboardingReceiveStep: View {
    let services: AppServices
    let progress: OnboardingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if progress.step == .done, let linked = progress.linkedReceipt {
                Text("첫 기록 받음").font(Theme.sectionLarge).foregroundStyle(Theme.Onboarding.ok)
                Text("\(linked.provider.name) · \(linked.receipt.project ?? "") · \(linked.receipt.at.formatted(date: .omitted, time: .shortened))")
                    .font(Theme.body).foregroundStyle(Theme.text)
            } else {
                ForEach(progress.tools, id: \.self) { provider in
                    row(provider)
                }
            }
            if case .serverDown(let reason) = progress.blocker {
                HStack(spacing: Theme.Spacing.m) {
                    Text(reason).foregroundStyle(Theme.Onboarding.problem)
                    Button("다시 시도") { services.retryIntegration() }
                }
                .font(Theme.captionLarge)
            } else if case .unlinked = progress.blocker, let text = OnboardingText.blocker(progress.blocker!) {
                Text(text).font(Theme.captionLarge).foregroundStyle(Theme.Onboarding.problem)
            }
        }
    }

    private func row(_ provider: AgentProvider) -> some View {
        let receipt = progress.input.receipts[provider].flatMap { $0.at >= progress.input.startedAt ? $0 : nil }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.m) {
                Text(provider.name).font(Theme.bodyMedium).foregroundStyle(Theme.text)
                Spacer()
                if receipt == nil, progress.blocker == .waiting {
                    ProgressView().controlSize(.small)
                }
                Text(receipt == nil ? "기다리는 중" : receipt?.project.map { "받음 · \($0)" } ?? "받음 · 등록 밖 폴더")
                    .font(Theme.captionLarge)
                    .foregroundStyle(receipt == nil ? Theme.Onboarding.muted
                                     : receipt?.project == nil ? Theme.Onboarding.problem : Theme.Onboarding.ok)
            }
            if receipt == nil {
                Text(OnboardingText.trust(provider)).font(Theme.captionLarge).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Onboarding.boxPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Onboarding.boxRadius))
    }
}
