import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 기록 탭의 저장 범위 표(`RecordScope`)가 실제 저장소·생성 지점과 맞는지(TRK-47).
@Suite struct RecordScopeTests {

    // MARK: - 저장 속성

    @Test func everyStoredAttributeIsClassified() {
        let schema = Set(WaypointStore.schema.entities.flatMap { entity in
            entity.attributes.map { "\(entity.name).\($0.name)" }
        })
        let table = Set(RecordScope.attributes.map { "\($0.entity).\($0.name)" })
        #expect(schema.subtracting(table).sorted() == [], "표에 없는 저장 속성")
        #expect(table.subtracting(schema).sorted() == [], "저장소에 없는 표 항목")
        #expect(table.count == RecordScope.attributes.count, "표에 같은 속성이 두 번")
    }

    @Test func everyEntityIsCovered() {
        let entities = Set(WaypointStore.schema.entities.map(\.name))
        #expect(entities == Set(RecordScope.attributes.map(\.entity)))
    }

    @Test func retentionFollowsRecordRetention() {
        let days = RecordRetention.days
        let labels = Dictionary(uniqueKeysWithValues: RecordScope.Item.allCases.map { ($0, $0.retention.label) })
        #expect(RecordScope.Item.allCases.filter { $0.retention == .kept } == [.projects, .cards, .github, .notes])
        #expect(labels[.projects] == "계속")
        #expect(labels[.prompts] == "\(days)일" && labels[.files] == "\(days)일")
        for item in [RecordScope.Item.sessions, .commits, .checks] {
            #expect(labels[item] == "\(days)일 · 카드에 이어진 것은 계속")
        }
        #expect(labels[.guides] == "\(days)일 · 최신 판은 계속")
        // 요청 이벤트는 통째로 지우고, 끝난 세션의 lastPrompt는 비운다. 마지막 요청 시각은 세션에 남는다.
        for key in ["kind", "promptId", "text"] {
            #expect(RecordScope.item(type: .note, kind: PromptRetention.promptKind, key: key) == .prompts)
        }
        #expect(RecordScope.attributes.first { $0.entity == "Session" && $0.name == "lastPrompt" }?.owner == .item(.prompts))
        #expect(RecordScope.attributes.first { $0.entity == "Session" && $0.name == "lastPromptAt" }?.owner == .item(.sessions))
    }

    @Test func guideDocsKeepContentAndVersions() {
        let guide = RecordScope.attributes.filter { $0.owner == .item(.guides) }.map { "\($0.entity).\($0.name)" }
        #expect(guide.contains("GuideDoc.content"))
        #expect(guide.contains("GuideVersion.content"))
        #expect(!RecordScope.notKept.contains("파일 내용"))
    }

    // MARK: - payload 키

    /// 생성 지점 목록. 새 `Event.record(` 호출이 생기면 여기서 실패한다 — 그 payload 키를 표에 더하고 숫자를 고친다.
    @Test func eventRecordCallSitesAreKnown() throws {
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared")
        var found: [String: Int] = [:]
        let files = try #require(FileManager.default.enumerator(at: shared, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = text.components(separatedBy: "Event.record(").count - 1
            if count > 0 { found[String(url.path.dropFirst(shared.path.count + 1))] = count }
        }
        #expect(found == [
            "GitHub/GitHubLog.swift": 1,
            "Guide/GuideLibrary.swift": 1,
            "Init/ProjectRegistry.swift": 1,
            "MCP/MCPTools.swift": 3,
            "MCP/MCPTools+Session.swift": 2,
            "MCP/MCPTools+Status.swift": 3,
            "Hooks/HookProcessor.swift": 2,
            "Hooks/HookProcessor+Events.swift": 5,
            "Rules/CardEditing.swift": 2,
            "Rules/CardEvidence.swift": 1,
            "Rules/CardLifecycle.swift": 6,
            "Rules/SessionProjectBinding.swift": 1,
            "Sample/SampleData.swift": 6,
        ])
    }

    /// 실제 생성 지점(훅 픽스처 전부·MCP 도구·카드 규칙·지침 문서·샘플)이 만든 payload 키가 모두 표에 있다.
    @Test func generatedPayloadKeysAreClassified() throws {
        var unknown: Set<String> = []
        var seen: Set<RecordScope.PayloadKey> = []
        func collect(_ context: ModelContext) throws {
            for event in try context.fetch(FetchDescriptor<Event>()) {
                let payload = event.payloadValues
                let kind = event.type == .note ? payload["kind"]?.stringValue : nil
                for key in payload.keys {
                    if let item = RecordScope.item(type: event.type, kind: kind, key: key) {
                        seen.insert(.init(type: event.type, kind: kind, key: key, item: item))
                    } else {
                        unknown.insert("\(event.typeRaw) kind=\(kind ?? "-") \(key)")
                    }
                }
            }
        }

        // 샘플 장면
        let (sampleContainer, sample) = try makeContext()
        _ = sampleContainer
        try SampleData.seedIfEmpty(sample, now: t0)
        try collect(sample)

        // 훅: 카드를 붙인 세션에 픽스처 전부
        let hooks = try HookHarness()
        try hooks.send("doc-SessionStart", at: t0)
        let session = try #require(try hooks.session())
        let card = hooks.project.makeCard(in: hooks.context, title: "영수증", criteria: [Criterion("swift test")], at: t0)
        CardLifecycle.attach(card, session, at: t0 + 1, in: hooks.context)
        for (index, name) in try hookFixtureNames().enumerated() {
            try hooks.send(name, at: t0 + 10 + Double(index))
        }
        CardEditing.setCriterion(card, at: 0, isDone: true, date: t0 + 500, in: hooks.context)
        try CardLifecycle.move(card, to: .done, at: t0 + 501, in: hooks.context)
        try collect(hooks.context)

        // MCP 도구
        let mcp = try MCPHarness()
        let sid = JSONValue.string(MCPHarness.sessionID)
        _ = try mcp.ok("card_create", ["project": "PRB", "title": "조건 카드", "sessionId": sid, "criteria": ["swift test"]])
        _ = try mcp.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        _ = try mcp.ok("card_note", ["id": "PRB-1", "text": "메모"])
        _ = try mcp.ok("card_handoff", ["id": "PRB-1", "nextSessionNote": "다음"])
        _ = try mcp.ok("card_evidence", ["id": "PRB-1", "command": "swift test", "outcome": "pass", "criterion": 1,
                                         "detail": "654개", "sessionId": sid])
        _ = try mcp.ok("card_update", ["id": "PRB-1", "criteria": [["text": "swift test", "done": true]]])
        _ = try mcp.ok("project_status", ["project": "PRB", "text": "상황", "sessionId": sid])
        _ = try mcp.ok("card_update", ["id": "PRB-1", "status": "done"])
        let other = Project(key: "OTH", name: "other", rootPath: "~/other", createdAt: t0)
        mcp.context.insert(other)
        _ = try mcp.ok("session_bind", ["project": "OTH", "sessionId": sid, "cwd": "/Users/me/other"])
        _ = try mcp.ok("session_bind", ["project": "PRB", "sessionId": "5e1f0c2a-0000-4000-8000-0000000000ff",
                                        "cwd": "/Users/me/probe"])
        try collect(mcp.context)

        // 정리 안 된 작업: 연결·넘김
        let (filedContainer, filed) = try makeContext()
        _ = filedContainer
        let fp = makeProject(filed)
        fp.makeCard(in: filed, title: "카드", at: t0)
        for id in ["aaaaaaaa-0001", "bbbbbbbb-0002"] {
            let s = makeSession(filed, fp, id: id, startedAt: t0)
            s.endedAt = t0 + 10
            Event.record(.fileChanged, in: filed, project: fp, session: s, at: t0 + 5, payload: ["path": "a.swift"])
        }
        let filer = MCPTools(context: filed, now: { t0 + 60 })
        _ = try filer.call("work_file", ["sessionId": "aaaaaaaa", "cardId": "LDG-1"])
        _ = try filer.call("work_file", ["sessionId": "bbbbbbbb"])
        try collect(filed)

        // 지침 문서
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-scope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# 지침\n".write(to: folder.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        let (guideContainer, guides) = try makeContext()
        _ = guideContainer
        let project = Project(key: "GDE", name: "guide", rootPath: folder.path, createdAt: t0)
        guides.insert(project)
        try GuideLibrary.register("CLAUDE.md", in: project, at: t0, context: guides)
        try collect(guides)

        // GitHub 이슈·PR
        let (githubContainer, github) = try makeContext()
        _ = githubContainer
        let gp = makeProject(github)
        let gs = makeSession(github, gp, id: "cccccccc-0003", startedAt: t0)
        for kind in GitHubKind.allCases {
            GitHubLog.record(GitHubCreated(kind: kind, repo: "me/app", number: 1, url: "https://github.com/me/app/x/1",
                                           title: "제목", state: .open, branch: kind == .pr ? "feat" : nil),
                             project: gp, card: nil, session: gs, at: t0, in: github)
        }
        try collect(github)

        #expect(unknown.sorted() == [], "표에 없는 payload 키")
        // 대표 키가 실제로 지나갔는지(생성 지점을 놓치지 않았는지)
        for type in [EventType.sessionStart, .sessionEnd, .cardCreated, .cardStatus, .cardAttached, .cardDetached,
                     .fileChanged, .commit, .check, .note, .guideSynced, .projectStatus, .sessionFiled, .githubIssue, .githubPR] {
            #expect(seen.contains { $0.type == type }, "생성되지 않은 종류: \(type.rawValue)")
        }
        for kind in [MCPTools.handoffNoteKind, CardEditing.criterionNoteKind, PromptRetention.promptKind,
                     SessionProjectBinding.boundNoteKind] {
            #expect(seen.contains { $0.kind == kind }, "생성되지 않은 메모 종류: \(kind)")
        }
    }

    @Test func payloadTableHasNoDuplicates() {
        let keys = RecordScope.payloadKeys.map { "\($0.type.rawValue)|\($0.kind ?? "-")|\($0.key)" }
        #expect(Set(keys).count == keys.count)
    }

    // MARK: - 이 Mac에만

    @Test func localItemsNameRealFiles() {
        let paths = RecordScope.localItems.flatMap(\.paths)
        #expect(paths.contains(StoreBackup.folderName))
        #expect(paths.contains(Outbox.fileName))
        #expect(paths.contains(GuidanceBackupStore.folderName))
        #expect(paths.contains(IntegrationInstallContext.backupFolderName))
        #expect(paths.contains(UsageSnapshot.fileName))
        #expect(paths.contains(SessionStatusSnapshot.fileName))
        #expect(!paths.contains("Waypoint.store"))  // 저장소는 「어디에」의 첫 줄
    }

    @Test func storePlaceFollowsICloud() {
        #expect(RecordScope.storePlace(iCloud: true).title == "iCloud · 이 Mac과 iPhone")
        #expect(RecordScope.storePlace(iCloud: false).title == "이 Mac")
        #expect(RecordScope.storePlace(iCloud: false).title != RecordScope.localPlaceTitle)
    }

    private func hookFixtureNames() throws -> [String] {
        let dir = try #require(Bundle.module.url(forResource: "hooks", withExtension: nil, subdirectory: "Fixtures"))
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") && !$0.contains("SessionEnd") }
            .map { String($0.dropLast(5)) }
            .sorted()
            + ["doc-SessionEnd"]
    }
}
