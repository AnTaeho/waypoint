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

/// 시험이 쓰는 임시 폴더의 뿌리. 프로세스마다 하나이고 끝날 때 통째로 지운다.
enum TestTemp {
    private static let prefix = "waypoint-tests-"

    static let root: URL = {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
        sweep(base)
        let url = base.appendingPathComponent("\(prefix)\(getpid())", isDirectory: true)
        try? fm.removeItem(at: url)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: TestTemp.root) }
        return url
    }()

    /// 죽은 프로세스가 남긴 뿌리를 지운다. 살아 있는 다른 실행의 것은 둔다.
    private static func sweep(_ base: URL) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] where name.hasPrefix(prefix) {
            guard let pid = pid_t(name.dropFirst(prefix.count)), pid != getpid() else { continue }
            if kill(pid, 0) == -1, errno == ESRCH { try? fm.removeItem(at: base.appendingPathComponent(name)) }
        }
    }
}

/// 임시 폴더의 SQLite 저장소(저장 실패·다른 context 저장을 실제 저장소로 확인할 때).
func makeDiskContainer(_ label: String = "test") throws -> ModelContainer {
    let url = TestTemp.root
        .appendingPathComponent("waypoint-\(label)-\(UUID().uuidString)").appendingPathComponent("t.store")
    return try WaypointStore.makeContainer(url: url)
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
