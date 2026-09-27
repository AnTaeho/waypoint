import Foundation

/// `SessionStart` 응답 본문(대화 컨텍스트에 주입되는 짧은 텍스트). Claude가 읽는 글이라 화면 문구 규칙과 별개다.
public enum SessionContext {

    public static let nextLimit = 5
    public static let noteLimit = 3

    /// 등록되지 않은 폴더에서 연 세션에 주는 한 줄.
    public static let unregistered = "Waypoint: 이 폴더는 Waypoint에 없음. `/tracker init`으로 등록할 수 있음."

    /// 프로젝트 키, 세션 ID, 다음 할 일 상위 5개, 이 프로젝트의 다른 작업중 카드, 직전 세션 메모.
    public static func text(
        project: Project,
        session: Session,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> String {
        let cards = (project.cards ?? []).filter { $0.status != .archived }
        var lines = [
            "Waypoint 프로젝트: \(project.key) (\(project.name))",
            "Waypoint 세션 ID: \(session.id)",
        ]

        let next = cards.filter { $0.status == .next }.sorted { $0.number < $1.number }.prefix(nextLimit)
        if !next.isEmpty {
            lines.append("다음 할 일:")
            lines += next.map { "- \($0.displayID) \($0.title)" }
        }

        let others = DashboardQuery.rows(for: project, now: now, stallTimeout: stallTimeout)
            .filter { $0.session !== session && $0.session.parent !== session }
        if !others.isEmpty {
            lines.append("다른 세션에서 작업중:")
            lines += others.map { row in
                let stalled = row.workState == .stalled ? ", 멈춤" : ""
                return "- \(row.card.displayID) \(row.card.title) (\(SessionFormat.label(for: row.session))\(stalled))"
            }
        }

        let notes = cards
            .filter { !($0.nextSessionNote ?? "").isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(noteLimit)
        if !notes.isEmpty {
            lines.append("직전 세션 메모:")
            lines += notes.map { "- \($0.displayID): \($0.nextSessionNote ?? "")" }
        }
        return lines.joined(separator: "\n")
    }
}
