import Foundation

public struct ActivityFilter: Equatable {
    public var provider = "all"
    public var card = "all"
    public var session = "all"
    public init() {}
    public var isActive: Bool { provider != "all" || card != "all" || session != "all" }
}

public struct ActivityEntry: Identifiable {
    public let id: UUID
    public let at: Date
    public let card: Card?
    public let type: EventType
    public let kind: String
    public var text: String
    public var detail: String
    public var count = 1
    public var added = 0
    public var removed = 0
}

public struct ActivitySessionGroup: Identifiable {
    public let id: String
    public let session: Session?
    public let at: Date
    public let entries: [ActivityEntry]
    public var title: String {
        entries.first(where: { $0.kind == PromptRetention.promptKind && $0.detail == ActivityEntryFormat.promptDetail })?.text
            ?? session.map(SessionFormat.label(for:)) ?? "카드·프로젝트 기록"
    }
    public var summary: String {
        let files = Set(entries.filter { $0.type == .fileChanged }.map(\.text)).count
        let commits = entries.filter { $0.type == .commit }.count
        let completed = entries.filter { $0.kind == "done" }.count
        return [files > 0 ? "파일 \(files)개" : nil, commits > 0 ? "커밋 \(commits)개" : nil,
                completed > 0 ? "완료 \(completed)건" : nil, "기록 \(entries.reduce(0) { $0 + $1.count })건"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

public struct ActivityDay: Identifiable {
    public let id: Date
    public let groups: [ActivitySessionGroup]
}

public enum ProjectActivity {
    /// 이벤트에 저장된 프로젝트를 기준으로 한다. 세션이 나중에 옮겨 가도 과거 기록은 이동하지 않는다.
    public static func days(events: [Event], projectID: UUID, filter: ActivityFilter = .init(),
                            search: String = "", calendar: Calendar = .current) -> [ActivityDay] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = events.filter { event in
            guard event.project?.id == projectID else { return false }
            if filter.provider != "all", (event.session?.provider.rawValue ?? "none") != filter.provider { return false }
            if filter.card != "all", (event.card?.id.uuidString ?? "none") != filter.card { return false }
            if filter.session != "all", (event.session?.id ?? "none") != filter.session { return false }
            guard !query.isEmpty else { return true }
            let payload = event.payloadValues.values.compactMap(\.stringValue)
            let fields = payload + [event.card?.title ?? "", event.card?.displayID ?? "", event.session?.id ?? ""]
            return fields.contains { $0.localizedStandardContains(query) }
        }
        let byDay = Dictionary(grouping: matching) { calendar.startOfDay(for: $0.at) }
        return byDay.keys.sorted(by: >).map { day in
            let bySession = Dictionary(grouping: byDay[day] ?? []) { $0.session?.id ?? "none" }
            let groups = bySession.compactMap { key, values -> ActivitySessionGroup? in
                let ordered = values.sorted { $0.at == $1.at ? $0.id.uuidString < $1.id.uuidString : $0.at > $1.at }
                let entries = coalesce(ordered.compactMap(ActivityEntryFormat.entry))
                guard let first = entries.first else { return nil }
                return ActivitySessionGroup(id: "\(day.timeIntervalSince1970)|\(key)", session: ordered.first?.session,
                                            at: first.at, entries: entries)
            }.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at > $1.at }
            return ActivityDay(id: day, groups: groups)
        }.filter { !$0.groups.isEmpty }
    }

    /// 연속된 동일 파일·카드 변경만 묶는다. 요청이나 메모를 가로질러 합치지 않는다.
    private static func coalesce(_ entries: [ActivityEntry]) -> [ActivityEntry] {
        var result: [ActivityEntry] = []
        for entry in entries {
            if entry.type == .fileChanged, let previous = result.last,
               previous.type == .fileChanged, previous.text == entry.text, previous.card?.id == entry.card?.id,
               previous.at.timeIntervalSince(entry.at) <= 5 * 60 {
                let i = result.count - 1
                result[i].count += 1; result[i].added += entry.added; result[i].removed += entry.removed
                result[i].detail = "\(result[i].count)회 변경 · +\(result[i].added) −\(result[i].removed)"
            } else { result.append(entry) }
        }
        return result
    }
}
