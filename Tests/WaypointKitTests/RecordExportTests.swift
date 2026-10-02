import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 기록 내보내기·모든 기록 지우기·다시 시작 명령(TRK-47). 저장소는 메모리나 임시 폴더만.
@Suite struct RecordExportTests {
    let stamp = StoreVersionStamp(appVersion: "0.0.1", build: "42")

    /// 두 프로젝트(카드·세션·연결·이벤트·지침 문서·버전)와 프로젝트 없는 세션·이벤트 하나씩.
    func seed(_ context: ModelContext) throws {
        for key in ["LDG", "WPT"] {
            let project = Project(key: key, name: "\(key) 앱", rootPath: "~/dev/\(key)", stack: ["Swift"], createdAt: t0)
            context.insert(project)
            let parent = project.makeCard(in: context, title: "\(key) 부모", at: t0)
            let card = project.makeCard(in: context, title: "\(key) 카드", body: "본문", parent: parent,
                                        criteria: [Criterion("swift test", isDone: true)], at: t0 + 1)
            card.nextSessionNote = "\(key) 다음 메모"
            let session = Session(id: "\(key)-session", cwd: "/Users/me/dev/\(key)", startedAt: t0)
            context.insert(session)
            session.project = project
            session.lastPrompt = "\(key) 요청"
            CardLifecycle.attach(card, session, at: t0 + 2, in: context)
            Event.record(.fileChanged, in: context, project: project, card: card, session: session, at: t0 + 3,
                         payload: ["path": .string("Sources/\(key).swift"), "added": 3, "removed": 1])
            Event.record(.note, in: context, card: card, at: t0 + 4.25,
                         payload: ["kind": .string(CardEditing.criterionNoteKind), "text": "swift test", "isDone": true])
            let doc = GuideDoc(relPath: "CLAUDE.md", content: "# \(key)", contentHash: "h", lastSyncedAt: t0)
            context.insert(doc)
            doc.project = project
            let version = GuideVersion(content: "# 옛 \(key)", at: t0, source: .local)
            context.insert(version)
            version.doc = doc
        }
        let stray = Session(id: "stray", cwd: "/tmp", startedAt: t0)
        context.insert(stray)
        Event.record(.sessionStart, in: context, session: stray, at: t0, payload: ["source": "startup"])
        try context.save()
    }

    // MARK: - 내보내기

    @Test func allExportRoundTrips() throws {
        let (container, context) = try makeContext()
        _ = container
        try seed(context)
        let document = try RecordExport.make(in: context, at: t0 + 0.5, stamp: stamp)
        let data = try RecordExport.encode(document)
        let decoded = try RecordExport.decode(data)
        #expect(decoded == document)
        #expect(try RecordExport.encode(decoded) == data)
        #expect(decoded.formatVersion == RecordExport.formatVersion)
        #expect(decoded.scope == "all")
        #expect(decoded.app == .init(version: "0.0.1", build: "42", schemaVersion: WaypointStore.currentSchemaVersion))
        #expect(decoded.exportedAt == t0 + 0.5)  // 밀리초까지
        #expect(decoded.projects.map(\.key) == ["LDG", "WPT"])
        #expect(decoded.unassigned?.sessions.map(\.id) == ["stray"])
        #expect(decoded.unassigned?.events.map(\.type) == ["session.start"])

        let ldg = try #require(decoded.projects.first)
        let card = try #require(ldg.cards.first { $0.number == 2 })
        #expect(card.displayID == "LDG-2")
        #expect(card.parent == "LDG-1")
        #expect(card.criteria == [Criterion("swift test", isDone: true)])
        #expect(card.nextSessionNote == "LDG 다음 메모")
        #expect(card.status == "active")
        #expect(card.sessions.map(\.sessionId) == ["LDG-session"])
        #expect(ldg.sessions.map(\.lastPrompt) == ["LDG 요청"])
        #expect(ldg.guideDocs.first?.content == "# LDG")
        #expect(ldg.guideDocs.first?.versions.map(\.content) == ["# 옛 LDG"])
        let file = try #require(ldg.events.first { $0.type == "file.changed" })
        #expect(file.card == "LDG-2")
        #expect(file.session == "LDG-session")
        #expect(file.payload == ["path": "Sources/LDG.swift", "added": 3, "removed": 1])
        let note = try #require(ldg.events.first { $0.type == "note" })
        #expect(note.payload?["isDone"] == .bool(true))
    }

    @Test func projectExportHasOnlyThatProject() throws {
        let (container, context) = try makeContext()
        _ = container
        try seed(context)
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first { $0.key == "WPT" })
        let data = try RecordExport.encode(try RecordExport.make(in: context, project: project, at: t0, stamp: stamp))
        let decoded = try RecordExport.decode(data)
        #expect(decoded.scope == "project")
        #expect(decoded.unassigned == nil)
        #expect(decoded.projects.map(\.key) == ["WPT"])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("LDG"))
        #expect(!text.contains("stray"))
        let wpt = try #require(decoded.projects.first)
        #expect(wpt.cards.allSatisfy { $0.displayID.hasPrefix("WPT-") })
        #expect(wpt.events.allSatisfy { $0.card.map { $0.hasPrefix("WPT-") } ?? true })
        #expect(wpt.sessions.map(\.id) == ["WPT-session"])
    }

    @Test func exportIsReadableJSONWithoutRuntimeState() throws {
        let (container, context) = try makeContext()
        _ = container
        try seed(context)
        let session = try #require(try context.fetch(FetchDescriptor<Session>()).first { $0.id == "LDG-session" })
        session.pendingToolsData = Data("{\"x\":1}".utf8)
        session.contextPendingID = "ctx-secret"
        session.claudePid = 4242
        let data = try RecordExport.encode(try RecordExport.make(in: context, at: t0, stamp: stamp))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n  \"app\" : {"))  // 들여쓴 정렬 JSON
        #expect(text.contains("\"formatVersion\" : 1"))
        #expect(text.contains("Sources/LDG.swift"))  // 사선을 가리지 않는다
        #expect(!text.contains("ctx-secret"))
        #expect(!text.contains("4242"))
        #expect(!text.contains("pendingTools"))
    }

    @Test func suggestedFileName() throws {
        let (container, context) = try makeContext()
        _ = container
        let project = makeProject(context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12)))
        #expect(RecordExport.suggestedFileName(project: nil, at: date) == "Waypoint-전체-2026-10-02.json")
        #expect(RecordExport.suggestedFileName(project: project, at: date) == "Waypoint-LDG-2026-10-02.json")
    }

    // MARK: - 지우기

    @Test func deleteAllEmptiesStoreAfterBackup() throws {
        let support = try StoreTemp()
        let container = try WaypointStore.makeContainer(url: support.store)
        let context = ModelContext(container)
        try seed(context)
        let before = try RecordWipe.counts(in: context)
        #expect(before == .init(projects: 2, cards: 4, sessions: 3, events: 9, guideDocs: 2))

        var order: [String] = []
        let (entry, deleted) = try RecordWipe.backUpAndDeleteAll(in: context) {
            order.append("backup")
            #expect(try context.fetchCount(FetchDescriptor<Project>()) == 2)  // 지우기 전에 뜬다
            return try support.backup.backupOpenStore(reason: .beforeDelete, stamp: stamp, at: t0)
        }
        order.append("deleted")
        #expect(order == ["backup", "deleted"])
        #expect(deleted == before)
        #expect(entry.info.reason == .beforeDelete)
        #expect(entry.id.hasSuffix("-beforeDelete"))
        #expect(try RecordWipe.counts(in: context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<CardSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<GuideVersion>()) == 0)

        // 다른 context(저장된 파일)에서도 비었다
        let fresh = ModelContext(container)
        #expect(try RecordWipe.counts(in: fresh).isEmpty)
        // 백업은 남아 있고 지우기 전 기록을 담았다
        #expect(support.backup.list().map(\.id) == [entry.id])
        #expect(try support.keys(in: entry) == ["LDG", "WPT"])
    }

    @Test func failedBackupDeletesNothing() throws {
        let (container, context) = try makeContext()
        _ = container
        try seed(context)
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            _ = try RecordWipe.backUpAndDeleteAll(in: context) { throw Boom() }
        }
        #expect(throws: RecordWipe.BackupBusy.self) {
            _ = try RecordWipe.backUpAndDeleteAll(in: context) { nil }
        }
        #expect(try RecordWipe.counts(in: context).projects == 2)
    }

    @Test func manualBackupWaitsForRunningBackup() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let daily = StoreDailyBackup(storeURL: support.store, stamp: stamp)
        #expect(daily.claimNow())
        #expect(try daily.runNow(reason: .manual, now: t0) == nil)  // 도는 중이면 뜨지 않는다
        daily.finish(nil)
        let entry = try #require(try daily.runNow(reason: .manual, now: t0))
        #expect(entry.info.reason == .manual)
        #expect(entry.info.method == .sqliteBackup)
        #expect(entry.info.build == "42")
        #expect(try support.keys(in: entry) == ["LDG"])
        // 직접 뜬 백업도 daily 판정의 「마지막 백업」이 된다
        #expect(try daily.runIfDue(now: t0 + 3600) == nil)
    }

    // MARK: - 문구·다시 시작

    @Test func backupLineText() {
        let entry = StoreBackup.Entry(
            url: URL(fileURLWithPath: "/tmp/x"),
            info: .init(reason: .beforeDelete, createdAt: t0, appVersion: "0.0.1", build: "1", schemaVersion: "1.0.0",
                        method: .sqliteBackup, files: ["Waypoint.store": 2_000_000, "Waypoint.store-wal": 0])
        )
        #expect(RecordFormat.reason(.upgrade) == "업데이트 전")
        #expect(RecordFormat.reason(.daily) == "매일")
        #expect(RecordFormat.reason(.manual) == "직접")
        #expect(RecordFormat.reason(.beforeRestore) == "복원 전")
        #expect(RecordFormat.backupLine(entry, now: t0).hasSuffix(" · 지우기 전 · 2 MB"))
        #expect(RecordFormat.wipeSummary(.init(projects: 4, cards: 110)) == "프로젝트 4개 · 카드 110개")
    }

    @Test func relaunchScriptForwardsEnvironmentOnly() {
        let script = AppRelaunch.script(pid: 4321, bundlePath: "/Apps/Way point.app", environment: [
            "WAYPOINT_SUPPORT_DIR": "/tmp/it's here", "WAYPOINT_CLOUDKIT": "0", "HOME": "/Users/me",
            AppRelaunch.hiddenKey: "1",
        ])
        #expect(script.hasPrefix("i=0; while /bin/kill -0 4321 2>/dev/null;"))
        #expect(script.contains("'/usr/bin/open' '-g' '-j'"))
        #expect(script.contains("'--env' 'WAYPOINT_SUPPORT_DIR=/tmp/it'\\''s here'"))
        #expect(script.contains("'--env' 'WAYPOINT_CLOUDKIT=0'"))
        #expect(!script.contains("HOME"))
        #expect(script.hasSuffix("'/Apps/Way point.app'"))
        let plain = AppRelaunch.script(pid: 1, bundlePath: "/A.app", environment: [:])
        #expect(plain.hasSuffix("'/usr/bin/open' '-g' '/A.app'"))
    }
}
