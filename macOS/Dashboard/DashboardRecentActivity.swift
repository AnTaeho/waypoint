import SwiftData
import SwiftUI
import WaypointKit

/// 본문에서는 최근 기록을 접어 두고, 자세한 기록은 기존 인스펙터에서도 볼 수 있다.
struct DashboardRecentActivity: View {
    let now: Date
    @Query private var events: [Event]

    init(now: Date) {
        self.now = now
        let shown = RecentEventFormat.shownTypes.map(\.rawValue)
        var descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { shown.contains($0.typeRaw) },
            sortBy: [SortDescriptor(\Event.at, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        _events = Query(descriptor)
    }

    var body: some View {
        let lines = RecentEventFormat.lines(from: events, now: now, limit: Theme.Dashboard.recentLimit)
        DisclosureGroup("최근 기록") {
            if lines.isEmpty {
                Text("최근 기록이 없습니다.").font(Theme.caption).foregroundStyle(Theme.textMuted)
                    .padding(.top, Theme.Spacing.m)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                RecentEventRow(line: line, now: now, showsDivider: index < lines.count - 1)
            }
        }
        .font(Theme.captionLargeMedium).tint(Theme.textMuted)
    }
}
