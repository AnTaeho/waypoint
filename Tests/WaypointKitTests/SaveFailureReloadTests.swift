import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// MCP 도구·프로젝트 등록·보드 끌어 놓기·카드 상세의 저장 실패 뒤 메인 context가 저장소 값으로 돌아오는지(TRK-34).
/// 모두 디스크 SQLite 저장소. 실패 직후 메모리 값이 저장소와 같고, 이어진 정상 저장에 실패한 변경이 섞이지 않아야 한다.
@Suite struct SaveFailureReloadTests {
    private enum SaveFailure: Error { case diskUnavailable }
    private let failing: (ModelContext) throws -> Void = { _ in throw SaveFailure.diskUnavailable }

    private func stored<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) throws -> [T] {
        try ModelContext(container).fetch(FetchDescriptor<T>())
    }

    // MARK: - MCP

    @Test func mcpCreateFailureLeavesNoStaleNumberOrCard() throws {
        let h = try MCPHarness(onDisk: true)
        h.server.saveContext = failing
        let (_, isError) = try h.call("card_create", ["project": "PRB", "title": "실패할 카드"])
        #expect(isError)
        // 실패 직후 메모리 값이 저장소와 같다
        let project = try #require(stored(Project.self, in: h.container).first)
        #expect(h.project.nextCardNumber == project.nextCardNumber)
        #expect(h.project.cards?.isEmpty == true)

        h.server.saveContext = { try $0.save() }
        let created = try h.ok("card_create", ["project": "PRB", "title": "다시 만든 카드"])
        #expect(created["id"] == "PRB-1")
        let cards = try stored(Card.self, in: h.container)
        #expect(cards.map(\.title) == ["다시 만든 카드"] && cards.first?.number == 1)
        #expect(try stored(Event.self, in: h.container).filter { $0.type == .cardCreated }.count == 1)
    }

    /// TRK-33의 실패 모양: 실패한 연결이 메모리에 남으면 다음 저장에 세션 없는 연결로 들어간다.
    @Test func mcpStartFailureLeavesNoStaleLink() throws {
        let h = try MCPHarness(onDisk: true)
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, at: t0)
        try h.context.save()
        let sid = JSONValue.string(MCPHarness.sessionID)

        h.server.saveContext = failing
        let (_, isError) = try h.call("card_start", ["id": "PRB-1", "sessionId": sid])
        #expect(isError)
        #expect(card.status == .next && card.cardSessions?.isEmpty == true)
        #expect(h.session.cardSessions?.isEmpty == true)

        h.server.saveContext = { try $0.save() }
        _ = try h.ok("card_create", ["project": "PRB", "title": "다른 카드", "kind": "idea"])
        #expect(try stored(CardSession.self, in: h.container).isEmpty)
        let reread = try #require(stored(Card.self, in: h.container).first { $0.number == 1 })
        #expect(reread.status == .next)

        _ = try h.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        let links = try stored(CardSession.self, in: h.container)
        #expect(links.count == 1 && links.first?.session?.id == MCPHarness.sessionID && links.first?.card?.number == 1)
    }

    // MARK: - 프로젝트 등록

    @Test func registerFailureThenSameKeySucceeds() throws {
        let container = try makeDiskContainer("registry")
        let context = ModelContext(container)
        let other = Project(key: "PRB", name: "probe", rootPath: "/tmp/elsewhere", createdAt: t0)
        context.insert(other)
        try context.save()
        let dir = try TempDir()
        try dir.write("CLAUDE.md", "# 지침\n")
        let draft = ProjectDraft(
            rootPath: dir.url.path, name: "Init Probe", key: "IPR", guideFiles: ["CLAUDE.md"],
            seedCards: [.init(title: "파서", status: .next, kind: .task), .init(title: "색", status: .idea, kind: .task)],
            createdAt: t0
        )

        #expect(throws: SaveFailure.self) {
            try ProjectRegistry.register(draft, at: t0, context: context, save: failing)
        }
        #expect(ProjectRegistry.takenKeys(in: context) == ["PRB"])
        #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(!context.hasChanges)

        let project = try ProjectRegistry.register(draft, at: t0 + 60, context: context)
        #expect(project.cards?.count == 2)
        let projects = try stored(Project.self, in: container)
        #expect(projects.map(\.key).sorted() == ["IPR", "PRB"])
        let cards = try stored(Card.self, in: container)
        #expect(cards.map(\.number).sorted() == [1, 2] && cards.allSatisfy { $0.project?.key == "IPR" })
        #expect(try stored(Event.self, in: container).filter { $0.type == .cardCreated }.count == 2)
    }

    // MARK: - 보드

    @Test func boardDropFailureRestoresStatus() throws {
        let container = try makeDiskContainer("board")
        let context = ModelContext(container)
        let p = makeProject(context)
        let card = p.makeCard(in: context, title: "a", status: .next, at: t0)
        try context.save()

        #expect(!BoardQuery.dropAndSave(card, on: .done, at: t0 + 1, in: context, save: failing))
        #expect(card.status == .next)
        #expect(card.events?.count == (try stored(Card.self, in: container).first?.events?.count))

        card.title = "고침"
        try context.save()
        let reread = try #require(stored(Card.self, in: container).first)
        #expect(reread.status == .next && reread.title == "고침")

        #expect(BoardQuery.dropAndSave(card, on: .done, at: t0 + 2, in: context))
        #expect(try stored(Card.self, in: container).first?.status == .done)
    }

    /// 놓을 수 없는 칸이면 아무것도 되돌리지 않는다(다른 저장 안 된 변경이 남는다).
    @Test func boardRefusedDropKeepsOtherChanges() throws {
        let container = try makeDiskContainer("board")
        let context = ModelContext(container)
        let p = makeProject(context)
        let card = p.makeCard(in: context, title: "a", status: .next, at: t0)
        try context.save()
        p.name = "바꾼 이름"
        #expect(!BoardQuery.dropAndSave(card, on: .active, at: t0 + 1, in: context, save: failing))
        #expect(p.name == "바꾼 이름" && context.hasChanges)
    }

    // MARK: - 카드 상세

    @Test func completeFailureKeepsLinkAndStatus() throws {
        let container = try makeDiskContainer("detail")
        let context = ModelContext(container)
        let p = makeProject(context)
        let s = makeSession(context, p, id: "S1", lastSeenAt: t0)
        let card = p.makeCard(in: context, title: "a", status: .next, criteria: [Criterion("하나")], at: t0)
        CardLifecycle.attach(card, s, at: t0, in: context)
        try context.save()
        #expect(card.status == .active && card.openCardSessions.count == 1)

        #expect(!CardEditing.completeAndSave(card, at: t0 + 10, in: context, save: failing))
        #expect(card.status == .active && card.openCardSessions.count == 1)
        #expect(s.cardSessions?.first?.detachedAt == nil)

        #expect(CardEditing.setCriterionAndSave(card, at: 0, isDone: true, date: t0 + 20, in: context))
        let reread = try #require(stored(Card.self, in: container).first)
        #expect(reread.status == .active && reread.openCardSessions.count == 1)
        #expect(reread.criteria.map(\.isDone) == [true])
        #expect(try stored(CardSession.self, in: container).first?.detachedAt == nil)
    }

    @Test func criterionFailureRestoresCheckAndEvents() throws {
        let container = try makeDiskContainer("detail")
        let context = ModelContext(container)
        let p = makeProject(context)
        let card = p.makeCard(in: context, title: "a", status: .next,
                              criteria: [Criterion("하나"), Criterion("둘")], at: t0)
        try context.save()
        let eventsBefore = card.events?.count ?? 0

        #expect(!CardEditing.setCriterionAndSave(card, at: 0, isDone: true, date: t0 + 1, in: context, save: failing))
        #expect(card.criteria.map(\.isDone) == [false, false])
        #expect(card.events?.count == eventsBefore)
        #expect(events(card, .note).isEmpty)

        #expect(CardEditing.setCriterionAndSave(card, at: 1, isDone: true, date: t0 + 2, in: context))
        let reread = try #require(stored(Card.self, in: container).first)
        #expect(reread.criteria.map(\.isDone) == [false, true])
        let notes = try stored(Event.self, in: container).filter { $0.type == .note }
        #expect(notes.count == 1)
        // 바꿀 것이 없으면 저장하지 않고 false
        #expect(!CardEditing.setCriterionAndSave(card, at: 1, isDone: true, date: t0 + 3, in: context, save: failing))
    }
}
