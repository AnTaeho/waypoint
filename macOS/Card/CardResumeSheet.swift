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
    @State private var openFailed = false
    @State private var showsPrompt = false

    var body: some View {
        LiveDataTimeline { _ in content }
    }

    @ViewBuilder private var content: some View {
        let prompt = CardResumeContext.text(card: card, provider: provider)
        let status = CardResumeStatus.of(card, attempt: resumeAttempt)
        let plan = prompt == nil ? nil : card.project.flatMap { ToolLauncher.plan(provider: provider, rootPath: $0.rootPath) }
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("\(card.displayID) · 작업 이어가기").font(Theme.pageTitle).lineLimit(2)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    CardResumeSummaryView(summary: CardResumeSummary(card: card))
                    if let prompt {
                        DisclosureGroup("복사할 문맥", isExpanded: $showsPrompt) {
                            Text(prompt).font(Theme.mono).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Spacing.l)
                                .background(Theme.bgSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        }.font(Theme.body)
                    }
                }
            }
            Picker("이어갈 도구", selection: $provider) {
                ForEach(AgentProvider.allCases, id: \.self) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented)
            if let project = card.project {
                Text((project.rootPath as NSString).expandingTildeInPath)
                    .font(Theme.mono).textSelection(.enabled)
            }
            Text(status.label).font(Theme.captionLarge)
                .foregroundStyle(status.isConnected ? Theme.done : prompt == nil ? Theme.liveText : Theme.textMuted)
            HStack {
                feedback(prompt: prompt)
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
                if let plan {
                    Button("\(provider.name)에서 열기") { open(plan) }.buttonStyle(.bordered)
                }
                Button("\(provider.name)용 문맥 복사") { copy() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(prompt == nil)
            }
        }
        .padding(Theme.Spacing.pageH)
        .frame(width: Theme.Resume.width, height: Theme.Resume.height)
        .background(Theme.bg)
        .onChange(of: provider) { openFailed = false }
    }

    @ViewBuilder private func feedback(prompt: String?) -> some View {
        if copyFailed {
            Text("복사 실패").font(Theme.captionLarge).foregroundStyle(Theme.liveText)
        } else if openFailed {
            Text("터미널 열기 실패 · 문맥은 복사됨").font(Theme.captionLarge).foregroundStyle(Theme.liveText)
        } else if let prompt, copiedText == prompt {
            Label("복사됨", systemImage: "checkmark")
                .font(Theme.captionLarge).foregroundStyle(Theme.done)
        }
    }

    @discardableResult
    private func copy() -> Bool {
        openFailed = false
        guard let text = CardResumeContext.text(card: card, provider: provider) else { return false }
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(text, forType: .string)
        copiedText = success ? text : nil
        copyFailed = !success
        guard success else { return false }
        let attempt = CardResumeAttempt(card: card, provider: provider, at: Date())
        resumeAttempt = attempt
        services?.reliability.copied(attempt)
        return true
    }

    /// 문맥을 복사한 뒤 터미널에서 도구를 연다. 연결 여부는 새 세션이 카드에 붙을 때 따로 확인한다.
    private func open(_ plan: ToolLaunch.Plan) {
        guard copy() else { return }
        ToolLauncher.open(plan, provider: provider) { success in openFailed = !success }
    }
}
