import AppKit
import SwiftUI
import WaypointKit

/// 연결·해제 한 번의 계획과 결과. 계획을 보이고 확인 버튼으로 적용, 실패하면 원인과 다시 시도.
struct OnboardingTaskView: View {
    let task: OnboardingTask
    let home: URL
    /// 도구 단계에서 펼친 것이면 닫기 버튼
    var done: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(task.providers, id: \.self) { provider in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if done == nil {
                        Text(provider.name).font(Theme.bodyMedium).foregroundStyle(Theme.text)
                    }
                    if let item = task.items[provider] {
                        OnboardingTaskItem(item: item, provider: provider, action: task.action, home: home.path)
                    }
                }
            }
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.m) {
            switch task.phase {
            case .ready where task.canApply:
                Button(task.action == .install ? "연결" : "연결 해제") { Task { await task.apply() } }
                    .disabled(IntegrationEnvironment.installBlock != nil)
            case .applying:
                ProgressView().controlSize(.small)
            default:
                EmptyView()
            }
            if task.needsRetry || (task.phase == .ready && !task.canApply && !task.nothingToDo) {
                Button("다시 시도") { Task { await task.retry() } }
                    .disabled(IntegrationEnvironment.installBlock != nil)
            }
            if task.phase == .finished, !task.backupFolders.isEmpty {
                Button("백업 보기") { NSWorkspace.shared.activateFileViewerSelecting(task.backupFolders) }
            }
            if let done {
                Spacer()
                Button(task.phase == .ready && task.canApply ? "취소" : "닫기", action: done)
                    .disabled(task.phase == .applying)
            }
        }
        .font(Theme.captionLarge)
    }
}

/// 도구 하나: 원인 · 결과 · 계획 중 하나
private struct OnboardingTaskItem: View {
    let item: OnboardingTask.Item
    let provider: AgentProvider
    let action: IntegrationPlan.Action
    let home: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let error = item.error {
                Text(error).foregroundStyle(Theme.Onboarding.problem)
            } else if let result = item.result {
                if item.failures.isEmpty {
                    Text(action == .install ? "연결됨" : "연결 해제됨").foregroundStyle(Theme.Onboarding.ok)
                } else {
                    Text(action == .install ? "일부만 연결됨" : "일부만 해제됨").foregroundStyle(Theme.Onboarding.problem)
                    ForEach(item.failures, id: \.self) { Text($0).foregroundStyle(Theme.Onboarding.problem) }
                }
                if action == .install { Text(OnboardingText.trust(provider)).foregroundStyle(Theme.text) }
                notes(result.plan)
            } else if let plan = item.plan {
                if plan.isEmpty {
                    Text(action == .install ? "이미 연결됨" : "연결 없음").foregroundStyle(Theme.Onboarding.ok)
                } else {
                    ForEach(plan.files, id: \.path) { change in
                        Text(OnboardingText.change(change, home: home)).font(Theme.monoCaption)
                    }
                    ForEach(Array(plan.commands.enumerated()), id: \.offset) { Text(OnboardingText.command($1)) }
                }
                notes(plan)
            }
        }
        .font(Theme.captionLarge)
        .foregroundStyle(Theme.textSecondary)
        .textSelection(.enabled)
    }

    private func notes(_ plan: IntegrationPlan) -> some View {
        ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
            Text(OnboardingText.note(note)).foregroundStyle(Theme.Onboarding.muted)
        }
    }
}
