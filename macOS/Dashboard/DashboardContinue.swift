import SwiftUI
import WaypointKit

struct DashboardContinue: View {
    let rows: [DashboardRow]
    let cards: [Card]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("확인하고 이어가기").font(Theme.sectionLarge)
            if rows.isEmpty && cards.isEmpty {
                DashboardEmpty(message: "대기 중인 작업이나 이어갈 메모가 없습니다.")
            }
            if !rows.isEmpty {
                DisclosureGroup("대기·활동 없음 \(rows.count)개", isExpanded: $showsStalled) {
                    VStack(spacing: Theme.Spacing.m) {
                        ForEach(rows) { row in DashboardWorkTile(row: row, now: now) }
                    }.padding(.top, Theme.Spacing.m)
                }
                .font(Theme.captionLargeMedium).tint(Theme.liveText)
            }
            ForEach(Array(cards.prefix(Theme.Dashboard.resumeLimit))) { card in
                NavigationLink(value: card) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("직전 세션 메모 · \(card.displayID)")
                            .font(Theme.caption).foregroundStyle(Theme.textMuted)
                        Text(card.title).font(Theme.cardTitle).foregroundStyle(Theme.text).lineLimit(2)
                        Text(card.nextSessionNote ?? "")
                            .font(Theme.body).foregroundStyle(Theme.textMuted).lineLimit(4)
                        Text("메모와 카드 보기 →").font(Theme.captionLargeMedium).foregroundStyle(Theme.liveText)
                    }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.panel)
                            .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
                    }
                }.buttonStyle(.plain)
            }
            DashboardRecentActivity(now: now)
        }
    }

    @State private var showsStalled = true
}
