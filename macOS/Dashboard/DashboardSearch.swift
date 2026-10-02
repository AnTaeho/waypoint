import Foundation
import WaypointKit

/// 작업중 표의 프로젝트 묶음(검색으로 줄을 거른 뒤).
struct ActiveWorkSection: Identifiable {
    let project: Project
    let rows: [DashboardRow]
    var id: UUID { project.id }
}

/// 대시보드 검색: 프로젝트 이름·키, 카드 제목·ID, 카드 없는 세션의 요청 문장.
enum DashboardSearch {

    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func matches(_ card: Card, _ query: String) -> Bool {
        card.title.localizedCaseInsensitiveContains(query)
            || card.displayID.localizedCaseInsensitiveContains(query)
    }

    static func matches(_ project: Project, _ query: String) -> Bool {
        project.name.localizedCaseInsensitiveContains(query)
            || project.key.localizedCaseInsensitiveContains(query)
    }

    /// 프로젝트가 맞으면 모든 줄, 아니면 카드·요청 문장이 맞는 줄을 남긴다.
    static func sections(_ groups: [DashboardGroup], query: String?) -> [ActiveWorkSection] {
        groups.compactMap { group in
            let rows = query.map { q in
                group.rows.filter { row in
                    matches(group.project, q) || (row.card.map { matches($0, q) } ?? false)
                        || (row.card == nil && (row.session.lastPrompt?.localizedCaseInsensitiveContains(q) ?? false))
                }
            } ?? group.rows
            return rows.isEmpty ? nil : ActiveWorkSection(project: group.project, rows: rows)
        }
    }

    /// 상황판 타일의 카드 거르기: 프로젝트 이름·키가 맞으면 거르지 않고(nil), 아니면 맞는 카드만 남긴다.
    /// 작업중 줄의 검색(`sections`)과 같은 규칙이다.
    static func cardFilter(_ query: String?) -> (Project) -> ((Card) -> Bool)? {
        { project in
            guard let query, !matches(project, query) else { return nil }
            return { matches($0, query) }
        }
    }

    /// 상황판 타일: 이름·키가 맞거나, 맞는 카드(보관 제외)가 하나라도 있는 프로젝트.
    static func filter(_ projects: [Project], query: String?) -> [Project] {
        guard let query else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.key.localizedCaseInsensitiveContains(query)
                || (project.cards ?? []).contains { $0.status != .archived && matches($0, query) }
        }
    }
}
