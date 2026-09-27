import SwiftData
import SwiftUI
import WaypointKit

/// 인스펙터 「최근 기록」. 프로젝트가 선택돼 있으면 그 프로젝트 것만.
struct RecentEventsInspector: View {
    let projectID: PersistentIdentifier?

    @Query private var events: [Event]

    init(projectID: PersistentIdentifier?) {
        self.projectID = projectID
        let shown = RecentEventFormat.shownTypes.map(\.rawValue)
        var descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { shown.contains($0.typeRaw) },
            sortBy: [SortDescriptor(\Event.at, order: .reverse)]
        )
        descriptor.fetchLimit = Self.fetchLimit
        _events = Query(descriptor)
    }

    /// 보관 프로젝트·다른 프로젝트 것을 걸러도 15줄이 남도록 넉넉히 읽는다.
    private static let fetchLimit = 400

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("최근 기록")
                        .font(Theme.section)
                        .foregroundStyle(Theme.text)
                    let lines = RecentEventFormat.lines(from: scoped, now: timeline.date)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            RecentEventRow(line: line, now: timeline.date, showsDivider: index < lines.count - 1)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l + Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.bgPanel)
    }

    private var scoped: [Event] {
        guard let projectID else { return events }
        return events.filter { $0.project?.persistentModelID == projectID }
    }
}
