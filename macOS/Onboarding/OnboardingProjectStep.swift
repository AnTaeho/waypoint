import AppKit
import SwiftData
import SwiftUI
import WaypointKit

/// 프로젝트: 폴더를 골라 등록 창으로, 또는 그 폴더의 도구에서 /tracker init.
struct OnboardingProjectStep: View {
    let model: OnboardingModel
    let progress: OnboardingProgress
    @Environment(\.modelContext) private var context
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.m) {
                Button("폴더 고르기…") { model.pickFolder(context: context) }
                Button(copied ? "복사됨" : "/tracker init 복사", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
            }
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
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString("/tracker init", forType: .string) else { return }
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(Theme.Onboarding.copiedSeconds))
            copied = false
        }
    }
}
