import AppKit
import SwiftUI
import WaypointKit

struct CardResumeSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @AppStorage("resumeProvider") private var provider: AgentProvider = .codex
    @State private var copiedText: String?
    @State private var copyFailed = false

    var body: some View {
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
                Text(CardResumeContext.unavailableReason(card) ?? "재개 문맥을 만들 수 없습니다.")
                    .font(Theme.body).foregroundStyle(Theme.liveText)
                Spacer()
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
    }
}
