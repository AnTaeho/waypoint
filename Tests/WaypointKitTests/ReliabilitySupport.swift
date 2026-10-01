#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 신뢰성 시나리오(TRK-11)의 공통 무대. 실측 픽스처(`real-*`, `doc-codex-*`)의 세션 ID·폴더·파일만 바꿔 재생한다.
/// 등록 프로젝트: PRB(실측 폴더), OTH(옆 폴더), KIT(PRB 안에 따로 등록한 하위 폴더).
final class ReliabilityWorld {
    static let home = "/Users/antaeho"
    static let probe = "/Users/antaeho/workspace/waypoint-probe"
    static let other = "/Users/antaeho/workspace/other-app"
    static let nested = probe + "/packages/kit"

    let storeURL: URL?
    private(set) var container: ModelContainer
    private(set) var context: ModelContext
    private(set) var processor: HookProcessor
    let outboxDir: URL

    /// `onDisk`면 임시 SQLite 저장소(앱 재시작을 흉내 낼 때).
    init(onDisk: Bool = false, register: [(key: String, root: String)] = [
        ("PRB", ReliabilityWorld.probe), ("OTH", ReliabilityWorld.other), ("KIT", ReliabilityWorld.nested),
    ]) throws {
        if onDisk {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("waypoint-reliability-\(UUID().uuidString)").appendingPathComponent("t.store")
            storeURL = url
            container = try WaypointStore.makeContainer(url: url)
        } else {
            storeURL = nil
            container = try WaypointStore.makeContainer(inMemory: true)
        }
        context = ModelContext(container)
        processor = HookProcessor(context: context, home: Self.home, gitBranch: { _ in "main" })
        outboxDir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-reliability-outbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outboxDir, withIntermediateDirectories: true)
        for item in register { try registerProject(item.key, root: item.root) }
    }

    deinit { try? FileManager.default.removeItem(at: outboxDir) }

    @discardableResult
    func registerProject(_ key: String, root: String) throws -> Project {
        let project = Project(key: key, name: "프로젝트 \(key)", rootPath: root, createdAt: t0)
        context.insert(project)
        try context.save()
        return project
    }

    func project(_ key: String) throws -> Project {
        try #require(try context.fetch(FetchDescriptor<Project>()).first { $0.key == key }, "프로젝트 없음: \(key)")
    }

    func card(_ key: String, title: String, status: CardStatus = .next) throws -> Card {
        let card = try project(key).makeCard(in: context, title: title, status: status, at: t0)
        try context.save()
        return card
    }

    func session(_ id: String) throws -> Session? {
        try context.fetch(FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id })).first
    }

    /// MCP `card_start`처럼 세션을 카드에 잇는다.
    func attach(_ card: Card, to sessionID: String, at date: Date) throws {
        let session = try #require(try session(sessionID), "세션 없음: \(sessionID)")
        CardLifecycle.attach(card, session, at: date, in: context)
        try context.save()
    }

    /// 앱 재시작: 같은 저장 파일로 컨테이너·context·처리기를 새로 만든다(메모리의 대기 항목은 사라진다).
    func restart() throws {
        let url = try #require(storeURL, "디스크 저장소에서만 재시작할 수 있다")
        container = try WaypointStore.makeContainer(url: url)
        context = ModelContext(container)
        processor = HookProcessor(context: context, home: Self.home, gitBranch: { _ in "main" })
    }

    // MARK: - 훅 만들기

    /// 픽스처를 읽어 세션·폴더·필드를 바꾼 본문.
    func payload(_ name: String, session: String, cwd: String,
                 _ edit: (inout [String: Any]) -> Void = { _ in }) throws -> [String: Any] {
        var object = try #require(try JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
        object["session_id"] = session
        object["cwd"] = cwd
        edit(&object)
        return object
    }

    /// 실시간 POST와 같은 경로(서버 → 처리기).
    @discardableResult
    func live(_ object: [String: Any], at date: Date, provider: AgentProvider = .claude, pid: Int? = nil) throws -> String? {
        let data = try JSONSerialization.data(withJSONObject: object)
        return processor.handle(event: nil, json: data, at: date,
                                claudePid: provider == .claude ? pid : nil,
                                provider: provider, processPid: provider == .codex ? pid : nil)
    }

    /// 훅 스크립트가 outbox에 쓰는 한 줄. payload는 실제 스크립트의 필터(`OUTBOX_FILTER`)로 줄인 것이고
    /// (`OutboxTrimTests.trimmedLine`), `receivedAt`은 스크립트처럼 초 단위로 자른다.
    func appendOutbox(_ object: [String: Any], at date: Date, provider: AgentProvider = .claude) throws {
        let event = try #require(object["hook_event_name"] as? String)
        let raw = try JSONSerialization.data(withJSONObject: object)
        let entry = try #require(try OutboxTrimTests.trimmedLine(raw, event: event, provider: provider))
        let payload = try JSONSerialization.jsonObject(with: entry.payload)
        var line: [String: Any] = ["event": event, "receivedAt": Int(date.timeIntervalSince1970),
                                   "trimmed": true, "payload": payload]
        if provider == .codex { line["provider"] = "codex" }
        let data = try JSONSerialization.data(withJSONObject: line)
        let url = outboxDir.appendingPathComponent(Outbox.fileName)
        let text = String(decoding: data, as: UTF8.self) + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    func absorb() -> Outbox.DrainResult {
        processor.absorbOutbox(directory: outboxDir)
    }
}

// MARK: - 불변식

/// 기대하는 기록 한 건. `detail`은 이벤트를 가르는 값(파일 경로·커밋 해시·요청 문장·검증 명령).
struct ExpectedRecord: CustomStringConvertible {
    let type: EventType
    let session: String
    let project: String?
    let card: String?
    let detail: String
    var description: String { "\(type.rawValue)[\(session)] \(detail) → \(project ?? "-")/\(card ?? "-")" }
}

enum Reliability {
    /// 시나리오가 판정하는 사실 기록. 연결·상태 이벤트는 따로 본다.
    static let factTypes: Set<EventType> = [.fileChanged, .commit, .check, .note]

    static func detail(_ event: Event) -> String? {
        let values = event.payloadValues
        switch event.type {
        case .fileChanged: return values["path"]?.stringValue
        case .commit: return values["hash"]?.stringValue
        case .check: return values["command"]?.stringValue
        case .note:
            guard values["kind"]?.stringValue == "user.prompt" else { return nil }
            return values["text"]?.stringValue
        default: return nil
        }
    }

    /// 오귀속·중복·손실 0건을 한 번에 검사한다.
    /// - `records`: 기대하는 사실 기록 전부. 저장소의 사실 기록과 1:1이어야 한다(없으면 손실, 남으면 오귀속, 둘이면 중복).
    /// - `sessions`: 세션 ID → 기대 프로젝트 키(nil이면 세션이 없어야 한다).
    /// - `starts`: 세션 ID → `session.start` 수(기본 1, 다시 살아난 세션만 따로 준다).
    static func verify(_ world: ReliabilityWorld, records: [ExpectedRecord], sessions: [String: String?],
                       starts: [String: Int] = [:], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let context = ModelContext(world.container) // 저장된 것만 본다
        let events = try context.fetch(FetchDescriptor<Event>())
        let facts = events.filter { factTypes.contains($0.type) && detail($0) != nil }

        var unmatched = facts
        for expected in records {
            let matches = unmatched.indices.filter { index in
                let event = unmatched[index]
                return event.type == expected.type && event.session?.id == expected.session
                    && detail(event) == expected.detail && event.card?.displayID == expected.card
            }
            #expect(!matches.isEmpty, "기록 손실: \(expected)", sourceLocation: sourceLocation)
            #expect(matches.count <= 1, "중복 기록 \(matches.count)건: \(expected)", sourceLocation: sourceLocation)
            guard let first = matches.first else { continue }
            #expect(unmatched[first].project?.key == expected.project,
                    "오귀속: \(expected) 실제 \(unmatched[first].project?.key ?? "-")", sourceLocation: sourceLocation)
            for index in matches.reversed() { unmatched.remove(at: index) }
        }
        for event in unmatched {
            Issue.record("기대 밖 기록(오귀속·중복): \(event.type.rawValue)[\(event.session?.id ?? "-")] \(detail(event) ?? "") → \(event.project?.key ?? "-")/\(event.card?.displayID ?? "-")",
                         sourceLocation: sourceLocation)
        }

        let stored = try context.fetch(FetchDescriptor<Session>())
        #expect(!stored.contains { $0.id.isEmpty }, "ID 없는 세션", sourceLocation: sourceLocation)
        #expect(Set(stored.map(\.id)).count == stored.count, "같은 ID의 세션이 둘", sourceLocation: sourceLocation)
        for (id, key) in sessions {
            let session = stored.first { $0.id == id }
            if let key {
                #expect(session?.project?.key == key, "세션 \(id) 프로젝트: \(session?.project?.key ?? "없음") ≠ \(key)",
                        sourceLocation: sourceLocation)
                let count = (session?.events ?? []).filter { $0.type == .sessionStart }.count
                #expect(count == (starts[id] ?? 1), "세션 \(id) 시작 기록 \(count)건", sourceLocation: sourceLocation)
            } else {
                #expect(session == nil, "세션 \(id)이 생기면 안 된다", sourceLocation: sourceLocation)
            }
        }
        let links = try context.fetch(FetchDescriptor<CardSession>())
        #expect(!links.contains { $0.card == nil || $0.session == nil }, "주인 없는 카드 연결", sourceLocation: sourceLocation)
        for link in links where link.isOpen {
            #expect(link.card?.project?.id == link.session?.project?.id,
                    "다른 프로젝트 카드에 열린 연결: \(link.card?.displayID ?? "-") ← \(link.session?.id ?? "-")",
                    sourceLocation: sourceLocation)
        }
    }
}
#endif
