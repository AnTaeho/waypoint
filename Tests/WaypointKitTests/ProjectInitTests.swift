import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// `project_init` 도구: 실제 임시 폴더와 초안 큐를 갖춘 서버.
struct InitHarness {
    let container: ModelContainer
    let context: ModelContext
    let dir: TempDir
    let drafts = ProjectDraftQueue()
    let server: MCPServer
    var root: String { ProjectMatcher.normalize(dir.url.path) }

    init() throws {
        (container, context) = try makeContext()
        dir = try TempDir()
        try dir.write("CLAUDE.md", "# 지침\n")
        try dir.write("docs/NOTES.md", "메모\n")
        try dir.write("src/main.swift", "print(1)\n")
        let other = Project(key: "PRB", name: "probe", rootPath: "/tmp/elsewhere", createdAt: t0)
        context.insert(other)
        try context.save()
        server = MCPServer(context: context, drafts: drafts, now: { t0 })
    }

    func call(_ arguments: JSONValue) throws -> (JSONValue, Bool) {
        let reply = try #require(server.handle([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "project_init", "arguments": arguments],
        ]))
        let result = try #require(reply["result"])
        let text = try #require(result["content"]?.arrayValue?.first?["text"]?.stringValue)
        return (try #require(JSONValue.parse(Data(text.utf8))), result["isError"]?.boolValue ?? false)
    }

    func projects() throws -> [Project] { try context.fetch(FetchDescriptor<Project>()) }
}

@Suite struct ProjectInitToolTests {
    @Test func pendingDraftWithCheckedFiles() throws {
        let h = try InitHarness()
        let (value, isError) = try h.call([
            "cwd": .string(h.dir.url.path + "/"),
            "name": "Init Probe", "key": "ipr", "summary": " 가짜 CLI ",
            "stack": ["Swift", "swift", " ", "CLI"],
            "guideFiles": ["CLAUDE.md", .string(h.dir.url.path + "/docs/NOTES.md"), "README.md", "src", "../x.md", "CLAUDE.md"],
            "seedCards": [
                ["title": "파서 고치기", "status": "next"],
                ["title": "색 출력", "status": "idea", "body": "나중에"],
                ["title": "날짜 버그", "kind": "bug"],
            ],
        ])
        #expect(!isError, "\(value.serializedString)")
        #expect(value["status"] == "pending")
        #expect(value["message"]?.stringValue == MCPTools.initPendingMessage)
        #expect(value["missingGuideFiles"] == ["README.md", "src", "../x.md"])
        #expect(value["warnings"] == nil)
        #expect(value["replacedDraft"] == false)

        let draft = try #require(h.drafts.current)
        #expect(draft.rootPath == h.root)
        #expect(draft.name == "Init Probe" && draft.key == "IPR" && draft.summary == "가짜 CLI")
        #expect(draft.stack == ["Swift", "CLI"])
        #expect(draft.guideFiles == ["CLAUDE.md", "docs/NOTES.md"])
        #expect(draft.seedCards.map(\.title) == ["파서 고치기", "색 출력", "날짜 버그"])
        #expect(draft.seedCards.map(\.status) == [.next, .idea, .next])
        #expect(draft.seedCards.map(\.kind) == [.task, .idea, .bug])
        #expect(draft.seedCards[1].body == "나중에")
        // 도구는 저장소를 바꾸지 않는다
        #expect(try h.projects().count == 1)
    }

    @Test func sameFolderReplacesDraft() throws {
        let h = try InitHarness()
        let other = try TempDir()
        _ = try h.call(["cwd": .string(h.dir.url.path), "name": "one"])
        _ = try h.call(["cwd": .string(other.url.path), "name": "other"])
        let (value, _) = try h.call(["cwd": .string(h.dir.url.path), "name": "two"])
        #expect(value["replacedDraft"] == true)
        #expect(h.drafts.drafts.map(\.name) == ["two", "other"])
        h.drafts.remove(h.drafts.drafts[0].id)
        #expect(h.drafts.current?.name == "other")
    }

    @Test func badOrTakenKeyStillMakesDraftWithWarning() throws {
        let h = try InitHarness()
        let (taken, e1) = try h.call(["cwd": .string(h.dir.url.path), "name": "probe two", "key": "prb"])
        #expect(!e1)
        #expect(taken["warnings"]?.arrayValue?.first?.stringValue?.contains("이미 쓰는 키") == true)
        #expect(h.drafts.current?.key == "PRB")
        let (bad, e2) = try h.call(["cwd": .string(h.dir.url.path), "name": "probe two", "key": "P1"])
        #expect(!e2)
        #expect(bad["warnings"]?.arrayValue?.first?.stringValue?.contains("2–5자") == true)
        // 키를 안 주면 추천
        let (none, _) = try h.call(["cwd": .string(h.dir.url.path), "name": "Waypoint Init Probe"])
        #expect(none["draft"]?["key"] == "WIP")
        #expect(h.drafts.drafts.count == 1)
    }

    @Test func rejectsFoldersAndBadInput() throws {
        let h = try InitHarness()
        func error(_ args: JSONValue) throws -> String {
            let (value, isError) = try h.call(args)
            #expect(isError, "\(value.serializedString)")
            return value["error"]?.stringValue ?? ""
        }
        #expect(try error(["cwd": "/nonexistent/waypoint-xyz", "name": "a"]).contains("폴더 없음"))
        #expect(try error(["cwd": "relative/path", "name": "a"]).contains("절대 경로"))
        #expect(try error(["cwd": .string(h.dir.url.path + "/CLAUDE.md"), "name": "a"]).contains("폴더 없음"))
        #expect(try error(["cwd": .string(h.dir.url.path), "name": " "]).contains("name"))
        let nine = JSONValue.array((1...9).map { ["title": .string("c\($0)")] })
        #expect(try error(["cwd": .string(h.dir.url.path), "name": "a", "seedCards": nine]).contains("최대 8"))
        #expect(try error(["cwd": .string(h.dir.url.path), "name": "a", "seedCards": [["title": "x", "status": "done"]]])
            .contains("next·idea"))

        // 등록된 폴더(하위 폴더 포함)
        let p = Project(key: "IPR", name: "init", rootPath: h.root, createdAt: t0)
        h.context.insert(p)
        try h.context.save()
        #expect(try error(["cwd": .string(h.dir.url.path + "/src"), "name": "a"]).contains("이미 등록된 폴더: IPR"))
        // 보관된 프로젝트의 폴더
        p.archivedAt = t0
        try h.context.save()
        #expect(try error(["cwd": .string(h.dir.url.path), "name": "a"]).contains("보관된 프로젝트 IPR"))
        // 보관된 프로젝트의 하위 폴더는 새로 등록할 수 있다
        let (_, subError) = try h.call(["cwd": .string(h.dir.url.path + "/src"), "name": "src"])
        #expect(!subError)
        #expect(h.drafts.drafts.map(\.name) == ["src"])
    }

    @Test func withoutQueueFails() throws {
        let (_, ctx) = try makeContext()
        let server = MCPServer(context: ctx)
        let reply = try #require(server.handle([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "project_init", "arguments": ["cwd": "/tmp", "name": "a"]],
        ]))
        #expect(reply["result"]?["isError"] == true)
    }
}

@Suite struct ProjectRegistryTests {
    func draft(_ h: InitHarness, key: String = "IPR", guides: [String] = ["CLAUDE.md", "docs/NOTES.md"]) -> ProjectDraft {
        ProjectDraft(
            rootPath: h.dir.url.path + "/", name: " 초기화 실측 ", key: key, summary: "요약",
            stack: ["Swift", "Swift"], guideFiles: guides,
            seedCards: [
                .init(title: "파서", status: .next, kind: .task, body: "본문"),
                .init(title: "색 출력", status: .idea, kind: .idea),
                .init(title: "  ", status: .next, kind: .task),
            ]
        )
    }

    @Test func registerCreatesProjectGuidesAndCardsAtOnce() throws {
        let h = try InitHarness()
        let project = try ProjectRegistry.register(draft(h, key: "ipr"), at: t0 + 60, context: h.context)
        #expect(project.key == "IPR" && project.name == "초기화 실측")
        #expect(project.rootPath == h.root && project.createdAt == t0 + 60)
        #expect(project.stack == ["Swift"])

        let docs = (project.guideDocs ?? []).sorted { $0.relPath < $1.relPath }
        #expect(docs.map(\.relPath) == ["CLAUDE.md", "docs/NOTES.md"])
        #expect(docs[0].content == "# 지침\n")
        #expect(docs.allSatisfy { $0.versions?.map(\.source) == [.local] })

        let cards = (project.cards ?? []).sorted { $0.number < $1.number }
        #expect(cards.map(\.displayID) == ["IPR-1", "IPR-2"])
        #expect(cards.map(\.status) == [.next, .idea])
        #expect(cards.allSatisfy { $0.origin == .claude })
        #expect(cards[0].body == "본문")
        #expect(project.nextCardNumber == 3)

        let types = (project.events ?? []).map(\.type)
        #expect(types.filter { $0 == .guideSynced }.count == 2)
        #expect(types.filter { $0 == .cardCreated }.count == 2)
        #expect(events(cards[1], .cardCreated).first?.payloadValues == ["origin": "claude", "status": "idea"])

        // 새 context로 다시 읽어도 있다(저장됨)
        let fresh = ModelContext(h.container)
        #expect(try fresh.fetch(FetchDescriptor<Project>()).map(\.key).sorted() == ["IPR", "PRB"])
        #expect(try fresh.fetchCount(FetchDescriptor<GuideDoc>()) == 2)
        #expect(try fresh.fetchCount(FetchDescriptor<Card>()) == 2)
    }

    @Test func failuresLeaveNothing() throws {
        let h = try InitHarness()
        #expect(throws: ProjectRegistry.Failure.key(.taken)) {
            try ProjectRegistry.register(draft(h, key: "PRB"), at: t0, context: h.context)
        }
        #expect(throws: ProjectRegistry.Failure.key(.format)) {
            try ProjectRegistry.register(draft(h, key: "I1"), at: t0, context: h.context)
        }
        var noName = draft(h)
        noName.name = " "
        #expect(throws: ProjectRegistry.Failure.emptyName) {
            try ProjectRegistry.register(noName, at: t0, context: h.context)
        }
        // 지침 파일이 그사이 사라짐 → 프로젝트까지 되돌린다
        #expect(throws: ProjectRegistry.Failure.guideMissing("GONE.md")) {
            try ProjectRegistry.register(draft(h, guides: ["CLAUDE.md", "GONE.md"]), at: t0, context: h.context)
        }
        let fresh = ModelContext(h.container)
        #expect(try fresh.fetch(FetchDescriptor<Project>()).map(\.key) == ["PRB"])
        #expect(try fresh.fetchCount(FetchDescriptor<GuideDoc>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Event>()) == 0)

        // 같은 폴더(보관 포함)
        try ProjectRegistry.register(draft(h), at: t0, context: h.context)
        let registered = try #require(ProjectRegistry.project(atRoot: h.dir.url.path, in: h.context))
        try ProjectRegistry.archive(registered, at: t0, context: h.context)
        #expect(throws: ProjectRegistry.Failure.folderTaken("IPR")) {
            try ProjectRegistry.register(draft(h, key: "NEW"), at: t0, context: h.context)
        }
        var missingFolder = draft(h, key: "NEW")
        missingFolder.rootPath = "/nonexistent/waypoint-xyz"
        #expect(throws: ProjectRegistry.Failure.folderMissing) {
            try ProjectRegistry.register(missingFolder, at: t0, context: h.context)
        }
    }

    @Test func archiveAndUnarchive() throws {
        let h = try InitHarness()
        let project = try ProjectRegistry.register(draft(h), at: t0, context: h.context)
        try ProjectRegistry.archive(project, at: t0 + 60, context: h.context)
        #expect(project.archivedAt == t0 + 60)
        // 보관 중에도 키는 쓰는 것으로 본다
        #expect(ProjectRegistry.takenKeys(in: h.context).contains("IPR"))
        #expect(ProjectMatcher.project(for: h.root, in: try h.projects()) == nil)
        try ProjectRegistry.unarchive(project, context: h.context)
        #expect(project.archivedAt == nil)
        #expect(ProjectMatcher.project(for: h.root, in: try h.projects()) === project)
    }

    @Test func deleteCascadesAndKeepsFiles() throws {
        let h = try InitHarness()
        let project = try ProjectRegistry.register(draft(h), at: t0, context: h.context)
        let card = try #require(project.cards?.first)
        let session = makeSession(h.context, project, id: "s-1", startedAt: t0, lastSeenAt: t0)
        let sub = makeSession(h.context, project, id: "a-1", startedAt: t0, lastSeenAt: t0, parent: session)
        _ = CardLifecycle.attach(card, sub, at: t0, in: h.context)
        _ = CardLifecycle.attach(card, session, at: t0, in: h.context)
        Event.record(.note, in: h.context, card: card, at: t0, payload: ["text": "메모"])
        try h.context.save()
        #expect(try h.context.fetchCount(FetchDescriptor<CardSession>()) == 2)

        try ProjectRegistry.delete(project, context: h.context)
        let fresh = ModelContext(h.container)
        #expect(try fresh.fetch(FetchDescriptor<Project>()).map(\.key) == ["PRB"])
        #expect(try fresh.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<CardSession>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<GuideDoc>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<GuideVersion>()) == 0)
        #expect(try h.dir.read("CLAUDE.md") == "# 지침\n")
        #expect(try h.dir.read("docs/NOTES.md") == "메모\n")
    }
}

@Suite struct InitFormTests {
    let draft = ProjectDraft(
        rootPath: "/tmp/x", name: "x", key: "prb", guideFiles: ["CLAUDE.md", "docs/A.md"],
        seedCards: [.init(title: "a", status: .next, kind: .task), .init(title: "b", status: .idea, kind: .idea)]
    )

    @Test func defaultsCheckEverythingAndKeyIsChecked() {
        var form = InitForm(draft: draft)
        #expect(form.checkedGuides == ["CLAUDE.md", "docs/A.md"])
        #expect(form.checkedCards.count == 2)
        #expect(form.keyProblem(taken: ["PRB"]) == .taken)
        #expect(!form.canRegister(taken: ["PRB"]))
        form.key = " ipr"
        #expect(form.canRegister(taken: ["PRB"]))
        form.name = "  "
        #expect(!form.canRegister(taken: ["PRB"]))
    }

    @Test func registrationKeepsOnlyChecked() {
        var form = InitForm(draft: draft)
        form.key = "ipr"
        form.checkedGuides.remove("CLAUDE.md")
        form.checkedCards.remove(draft.seedCards[0].id)
        form.addStack(" Swift ")
        form.addStack("swift")
        form.addStack("")
        let r = form.registration
        #expect(r.key == "IPR")
        #expect(r.guideFiles == ["docs/A.md"])
        #expect(r.seedCards.map(\.title) == ["b"])
        #expect(r.stack == ["Swift"])
        #expect(r.rootPath == "/tmp/x")
    }
}
