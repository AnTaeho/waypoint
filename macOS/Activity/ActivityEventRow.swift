import SwiftUI
import WaypointKit

struct ActivityEventRow: View {
    let entry: ActivityEntry
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            Image(systemName: symbol).foregroundStyle(entry.kind == "done" ? Theme.done : Theme.textMuted)
                .frame(width: Theme.Activity.markerWidth)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text(entry.at.formatted(date: .omitted, time: .standard))
                        .font(Theme.monoCaption).foregroundStyle(Theme.textMuted)
                    if !entry.detail.isEmpty {
                        Text(entry.detail).font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
                    }
                }
                Text(entry.text).font(entry.type == .fileChanged ? Theme.mono : Theme.body)
                    .foregroundStyle(Theme.text).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let card = entry.card {
                    NavigationLink(value: card) {
                        Text("\(card.displayID) · \(card.title) →")
                            .font(Theme.captionLargeMedium).foregroundStyle(Theme.liveText).lineLimit(2)
                    }.buttonStyle(.plain)
                    if entry.kind == "handoff" { Text("카드를 열어 이어갈 메모와 작업 내용을 확인하세요.").font(Theme.caption).foregroundStyle(Theme.textMuted) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symbol: String {
        if entry.kind == "user.prompt" { return "text.bubble" }
        if entry.kind == "handoff" { return "arrow.turn.down.right" }
        if entry.kind == "done" { return "checkmark.circle" }
        switch entry.type {
        case .fileChanged: return "doc.text"
        case .commit: return "point.3.connected.trianglepath.dotted"
        case .note: return "note.text"
        case .sessionStart, .sessionEnd: return "clock"
        default: return "circle"
        }
    }
}
