import SwiftData
import SwiftUI
import WaypointKit

/// 프로젝트: 폴더를 골라 등록 창으로, 또는 그 폴더의 도구에서 /tracker init.
struct OnboardingProjectStep: View {
    let model: OnboardingModel
    let progress: OnboardingProgress
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Button("폴더 고르기…") { model.pickFolder(context: context) }
                .font(Theme.body)
                .controlSize(.large)
            if let root = model.chosenRoot {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(GuideFormat.displayPath(root)).font(Theme.monoCaption).foregroundStyle(Theme.textSecondary)
                    if case .registered(let key) = progress.input.project {
                        Text("\(key) · 등록됨").font(Theme.captionLarge).foregroundStyle(Theme.Onboarding.ok)
                    }
                }
            }
            if let blocker = progress.blocker, let text = OnboardingText.blocker(blocker) {
                Text(text).font(Theme.captionLarge).foregroundStyle(Theme.Onboarding.problem)
            }
            Text("또는 그 폴더의 Claude Code·Codex에서 /tracker init")
                .font(Theme.captionLarge).foregroundStyle(Theme.Onboarding.muted)
        }
    }
}
