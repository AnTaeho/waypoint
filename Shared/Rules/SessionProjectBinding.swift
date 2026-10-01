import Foundation
import SwiftData

/// 한 대화가 프로젝트를 전환해도 이전 카드·이벤트의 소속은 바꾸지 않는다.
public enum SessionProjectBinding {
    @discardableResult
    public static func bind(_ session: Session, to project: Project, at date: Date,
                            in context: ModelContext) -> [String] {
        guard session.project !== project else { return [] }
        var detached: [String] = []
        var seen = Set<UUID>()
        for card in session.openCardSessions.compactMap(\.card) where seen.insert(card.id).inserted {
            CardLifecycle.detach(card, session, at: date, in: context)
            detached.append(card.displayID)
        }
        let previous = session.project?.key
        session.project = project
        session.contextProjectKey = nil
        session.gitBranch = GitInfo.branch(at: project.rootPath)
        if date > session.lastSeenAt { session.lastSeenAt = date }
        Event.record(.note, in: context, project: project, session: session, at: date,
                     payload: ["kind": .string("project.bound"), "from": .string(previous ?? ""),
                               "to": .string(project.key)])
        return detached
    }
}
