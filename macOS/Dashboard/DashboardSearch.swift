import Foundation
import WaypointKit

/// 작업중 표의 프로젝트 묶음(검색으로 줄을 거른 뒤).
struct ActiveWorkSection: Identifiable {
    let project: Project
    let rows: [DashboardRow]
    var id: UUID { project.id }
}

/// 대시보드 검색: 카드 제목·displayID로 거른다.
enum DashboardSearch {

    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func matches(_ card: Card, _ query: String) -> Bool {
        card.title.localizedCaseInsensitiveContains(query)
            || card.displayID.localizedCaseInsensitiveContains(query)
    }

    /// 작업중 표: 맞는 카드의 줄만 남기고 빈 묶음은 뺀다. 카드 없는 세션 줄은 검색 중에는 빠진다.
    static func sections(_ groups: [DashboardGroup], query: String?) -> [ActiveWorkSection] {
        groups.compactMap { group in
            let rows = query.map { q in
                group.rows.filter { row in row.card.map { matches($0, q) } ?? false }
            } ?? group.rows
            return rows.isEmpty ? nil : ActiveWorkSection(project: group.project, rows: rows)
        }
    }

    /// 프로젝트 표: 이름·키가 맞거나, 맞는 카드(보관 제외)가 하나라도 있는 프로젝트.
    static func filter(_ projects: [Project], query: String?) -> [Project] {
        guard let query else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.key.localizedCaseInsensitiveContains(query)
                || (project.cards ?? []).contains { $0.status != .archived && matches($0, query) }
        }
    }
}
