import SwiftData
import SwiftUI
import WaypointKit

/// 연결 설정: 도구 → 연결 → 프로젝트 → 첫 기록 → 끝. 메인 창 시트.
struct OnboardingView: View {
    let services: AppServices
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }) private var projects: [Project]

    var body: some View {
        let progress = OnboardingProgress(input)
        VStack(alignment: .leading, spacing: Theme.Onboarding.gap) {
            OnboardingHeader(step: progress.step)
            ScrollView {
                content(progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity, alignment: .top)
            OnboardingFooter(progress: progress, model: model)
        }
        .padding(Theme.Onboarding.padding)
        .frame(width: Theme.Onboarding.width, height: Theme.Onboarding.height)
        .background(Theme.surface)
        .task(id: progress.step) { await poll(progress.step) }
        .onChange(of: progress.step, initial: true) { _, step in
            if step == .install, IntegrationEnvironment.installBlock == nil { model.prepareInstall() }
        }
    }

    @ViewBuilder
    private func content(_ progress: OnboardingProgress) -> some View {
        switch progress.step {
        case .tools: OnboardingToolsStep(services: services, model: model)
        case .install: OnboardingInstallStep(model: model, progress: progress)
        case .project: OnboardingProjectStep(model: model, progress: progress)
        case .receive, .done: OnboardingReceiveStep(services: services, progress: progress)
        }
    }

    private var input: OnboardingProgress.Input {
        let monitor = services.integration
        var receipts: [AgentProvider: IntegrationReceipt] = [:]
        for provider in AgentProvider.allCases { receipts[provider] = monitor.history.hooks[provider.rawValue] }
        return .init(requested: model.requested, selected: model.selected, installations: monitor.installations,
                     receipts: receipts, startedAt: model.startedAt,
                     serverProblem: OnboardingText.serverProblem(services.serverState),
                     projectCount: projects.count, project: model.projectChoice(context: context),
                     installBlock: IntegrationEnvironment.installBlock)
    }

    /// 연결·첫 기록 단계에서는 연결 상태를 주기적으로 다시 읽는다(기록 수신은 바로 반영된다).
    private func poll(_ step: OnboardingProgress.Step) async {
        guard step == .install || step == .receive else { return }
        while !Task.isCancelled {
            services.integration.refresh()
            try? await Task.sleep(for: .seconds(Theme.Onboarding.refreshSeconds))
        }
    }
}

/// 제목과 단계 점
private struct OnboardingHeader: View {
    let step: OnboardingProgress.Step
    private let steps: [(OnboardingProgress.Step, String)] = [
        (.tools, "도구"), (.install, "연결"), (.project, "프로젝트"), (.receive, "첫 기록"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Waypoint 연결").font(Theme.pageTitle).foregroundStyle(Theme.text)
            HStack(spacing: Theme.Spacing.l) {
                ForEach(steps, id: \.0) { item, title in
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(item <= step ? Theme.live : Theme.border)
                            .frame(width: Theme.Onboarding.stepDot, height: Theme.Onboarding.stepDot)
                        Text(title)
                            .font(item == step || (item == .receive && step == .done) ? Theme.captionLargeMedium : Theme.captionLarge)
                            .foregroundStyle(item <= step ? Theme.text : Theme.textMuted)
                    }
                }
            }
        }
    }
}

/// 닫기 · 이전 · 다음(끝)
private struct OnboardingFooter: View {
    let progress: OnboardingProgress
    let model: OnboardingModel

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button("닫기") { model.close() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if progress.step != .tools {
                Button("이전") { model.requested = progress.step == .done ? .project : progress.step.previous }
            }
            if progress.step == .done {
                Button("끝") { model.finish() }
                    .keyboardShortcut(.defaultAction)
            } else if progress.step != .receive {
                Button("다음") { model.requested = progress.step.next }
                    .keyboardShortcut(.defaultAction)
                    .disabled(progress.blocker != nil || busy)
            }
        }
        .font(Theme.body)
        .controlSize(.large)
    }

    private var busy: Bool {
        model.install?.phase == .applying || model.toolTask?.phase == .applying
    }
}
