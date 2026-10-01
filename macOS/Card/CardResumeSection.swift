import SwiftUI
import WaypointKit

struct CardResumeSection: View {
    let card: Card
    @State private var showsResume = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Label("작업 이어가기", systemImage: "arrow.turn.down.right").font(Theme.sectionLarge)
                Spacer()
                Button("재개 문맥 준비") { showsResume = true }
                    .buttonStyle(.bordered)
                    .disabled(CardResumeContext.unavailableReason(card) != nil)
            }
            Text(CardResumeContext.unavailableReason(card)
                 ?? "목표·인수인계 메모·남은 조건·변경 파일을 모아 Claude Code 또는 Codex에서 이어가세요.")
                .font(Theme.body).foregroundStyle(Theme.textMuted)
            if let note = card.nextSessionNote, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note).font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(3)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .sheet(isPresented: $showsResume) { CardResumeSheet(card: card) }
    }
}
