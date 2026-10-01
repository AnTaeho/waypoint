import SwiftData
import SwiftUI
import WaypointKit

struct ProjectActivityView: View {
    let project: Project
    let searchText: String
    @State private var filter = ActivityFilter()
    @State private var limit = 300
    var body: some View {
        ActivityFeed(project: project, searchText: searchText, limit: limit, filter: $filter) { limit += 300 }
            .background(Theme.bg).navigationTitle(project.name)
    }
}

private struct ActivityFeed: View {
    let project: Project
    let searchText: String
    let limit: Int
    @Binding var filter: ActivityFilter
    let loadMore: () -> Void
    @Query private var events: [Event]

    init(project: Project, searchText: String, limit: Int, filter: Binding<ActivityFilter>, loadMore: @escaping () -> Void) {
        self.project = project; self.searchText = searchText; self.limit = limit; self._filter = filter; self.loadMore = loadMore
        let id = project.id
        var query = FetchDescriptor<Event>(predicate: #Predicate { $0.project?.id == id },
                                          sortBy: [SortDescriptor(\Event.at, order: .reverse)])
        query.fetchLimit = limit
        _events = Query(query)
    }

    var body: some View {
        LiveDataTimeline { now in
            let days = ProjectActivity.days(events: events, projectID: project.id, filter: filter, search: searchText)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("프로젝트 활동").font(Theme.pageTitle).foregroundStyle(Theme.text)
                        Text("요청부터 변경, 완료와 다음 작업까지").font(Theme.body).foregroundStyle(Theme.textMuted)
                        ActivityFilters(events: events, cards: project.cards ?? [], filter: $filter)
                        Text("불러온 최근 \(events.count)건 기준 · 검색과 필터는 이 범위에 적용됩니다.")
                            .font(Theme.caption).foregroundStyle(Theme.textMuted)
                        Text("요청 이력은 이 버전부터 최대 300자씩 기록됩니다. 세션 정보가 없는 기록은 도구 정보 없음으로 분류합니다.")
                            .font(Theme.caption).foregroundStyle(Theme.textMuted)
                    }
                    if days.isEmpty {
                        ContentUnavailableView(filter.isActive || !searchText.isEmpty ? "조건에 맞는 활동이 없습니다" : "아직 기록된 활동이 없습니다",
                            systemImage: "clock", description: Text("새 작업이 기록되면 자동으로 표시됩니다. 이전 기록은 아래에서 더 불러올 수 있습니다."))
                    }
                    ForEach(days) { day in
                        Text(TimeFormat.day(day.id, now: now)).font(Theme.sectionLarge).foregroundStyle(Theme.text)
                        ForEach(day.groups) { group in
                            ActivitySessionSection(group: group, project: project, now: now,
                                initiallyExpanded: group.id == days.first?.groups.first?.id)
                        }
                    }
                    if events.count == limit {
                        Button("이전 기록 300건 더 보기", action: loadMore)
                            .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.m)
                    }
                }
                .padding(.horizontal, Theme.Spacing.pageH).padding(.vertical, Theme.Spacing.pageV)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
