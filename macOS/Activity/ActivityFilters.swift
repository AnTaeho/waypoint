import SwiftUI
import WaypointKit

struct ActivityFilters: View {
    let events: [Event]
    let cards: [Card]
    @Binding var filter: ActivityFilter

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.l) { controls }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) { controls }
        }
    }

    @ViewBuilder private var controls: some View {
        Picker("도구", selection: $filter.provider) {
            Text("전체 도구").tag("all")
            Text("Claude Code").tag("claude")
            Text("Codex").tag("codex")
            Text("도구 정보 없음").tag("none")
        }.fixedSize()
        Picker("카드", selection: $filter.card) {
            Text("전체 카드").tag("all")
            Text("카드 없는 기록").tag("none")
            ForEach(cards.sorted { $0.number > $1.number }) { card in
                Text("\(card.displayID) · \(card.title)").tag(card.id.uuidString)
            }
        }.frame(maxWidth: Theme.Activity.filterWidth)
        Picker("세션", selection: $filter.session) {
            Text("전체 세션").tag("all")
            Text("카드·프로젝트 기록").tag("none")
            ForEach(sessions, id: \.id) { session in
                Text("\(session.provider.name) · \(session.sourceID.prefix(8))").tag(session.id)
            }
        }.frame(maxWidth: Theme.Activity.filterWidth)
        if filter.isActive { Button("초기화") { filter = .init() }.fixedSize() }
    }

    private var sessions: [Session] {
        var seen = Set<String>()
        return events.compactMap(\.session).filter { seen.insert($0.id).inserted }
    }
}
