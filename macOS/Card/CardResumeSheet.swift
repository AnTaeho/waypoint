import AppKit
import SwiftUI
import WaypointKit

struct CardResumeSheet: View {
    let card: Card
    @Binding var resumeAttempt: CardResumeAttempt?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services: AppServices?
    @AppStorage("resumeProvider") private var provider: AgentProvider = .codex
    @State private var copiedText: String?
    @State private var copyFailed = false

    var body: some View {
        LiveDataTimeline { _ in content }
    }

    @ViewBuilder private var content: some View {
        let prompt = CardResumeContext.text(card: card, provider: provider)
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("\(card.displayID) · 작업 이어가기").font(Theme.pageTitle).lineLimit(2)
            Picker("이어갈 도구", selection: $provider) {
                ForEach(AgentProvider.allCases, id: \.self) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented)
            if let project = card.project {
                Text((project.rootPath as NSString).expandingTildeInPath)
                    .font(Theme.mono).textSelection(.enabled)
            }
            if let prompt {
                ScrollView {
                    Text(prompt).font(Theme.mono).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Spacing.l)
                }.background(Theme.bgSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            } else {
                Text(CardResumeContext.unavailableReason(card) ?? "재개 문맥 없음")
                    .font(Theme.body).foregroundStyle(Theme.liveText)
                Spacer()
            }
            if let resumeAttempt {
                Text(resumeAttempt.label(for: card)).font(Theme.captionLarge)
                    .foregroundStyle(resumeAttempt.state(for: card) == .connected ? Theme.done : Theme.textMuted)
            }
            HStack {
                if copyFailed {
                    Text("복사 실패")
                        .font(Theme.captionLarge).foregroundStyle(Theme.liveText)
                } else if let prompt, copiedText == prompt {
                    Label("복사됨", systemImage: "checkmark")
                        .font(Theme.captionLarge).foregroundStyle(Theme.done)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("\(provider.name)용 문맥 복사") { copy() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(prompt == nil)
            }
        }
        .padding(Theme.Spacing.pageH)
        .frame(width: Theme.Resume.width, height: Theme.Resume.height)
        .background(Theme.bg)
    }

    private func copy() {
        guard let text = CardResumeContext.text(card: card, provider: provider) else { return }
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(text, forType: .string)
        copiedText = success ? text : nil
        copyFailed = !success
        guard success else { return }
        let attempt = CardResumeAttempt(card: card, provider: provider, at: Date())
        resumeAttempt = attempt
        services?.reliability.copied(attempt)
    }
}
