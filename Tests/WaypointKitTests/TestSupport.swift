import Foundation
import SwiftData
@testable import WaypointKit

let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

func minutes(_ m: Double) -> TimeInterval { m * 60 }

/// in-memory 컨테이너. context가 컨테이너를 붙잡도록 둘 다 돌려준다.
func makeContext() throws -> (ModelContainer, ModelContext) {
    let container = try WaypointStore.makeContainer(inMemory: true)
    return (container, ModelContext(container))
}

func makeProject(_ ctx: ModelContext, key: String = "LDG", name: String = "가계부 앱") -> Project {
    let p = Project(key: key, name: name, createdAt: t0)
    ctx.insert(p)
    return p
}

func makeSession(
    _ ctx: ModelContext, _ project: Project, id: String,
    startedAt: Date = t0, lastSeenAt: Date? = nil, parent: Session? = nil
) -> Session {
    let s = Session(id: id, kind: parent == nil ? .main : .subagent, startedAt: startedAt, lastSeenAt: lastSeenAt)
    ctx.insert(s)
    s.project = project
    s.parent = parent
    return s
}

func events(_ card: Card, _ type: EventType) -> [Event] {
    (card.events ?? []).filter { $0.type == type }
}
