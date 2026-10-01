import SwiftUI
import WaypointKit

struct CardResumeSection: View {
    let card: Card
    @State private var showsResume = false
    @State private var resumeAttempt: CardResumeAttempt?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Label("작업 이어가기", systemImage: "arrow.turn.down.right").font(Theme.sectionLarge)
                Spacer()
                Button("재개 문맥 준비") { showsResume = true }
                    .buttonStyle(.bordered)
                    .disabled(CardResumeContext.unavailableReason(card) != nil)
            }
            if let resumeAttempt {
                Text(resumeAttempt.label(for: card)).font(Theme.captionLarge)
                    .foregroundStyle(resumeAttempt.state(for: card) == .connected ? Theme.done : Theme.textMuted)
            }
            if let reason = CardResumeContext.unavailableReason(card) {
                Text(reason).font(Theme.body).foregroundStyle(Theme.textMuted)
            }
            if let note = card.nextSessionNote, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let freshness = HandoffFreshness.evaluate(card) {
                    Text(freshness.label).font(Theme.captionLarge)
                        .foregroundStyle(freshness.changedFileCount > 0 ? Theme.liveText : Theme.textMuted)
                }
                Text(note).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(3)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .onChange(of: card.id) { resumeAttempt = nil }
        .sheet(isPresented: $showsResume) { CardResumeSheet(card: card, resumeAttempt: $resumeAttempt) }
    }
}
