import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// `ContextReload`가 기대는 SwiftData 동작을 디스크 저장소로 고정한다. 이 동작이 바뀌면 outbox 흡수와 저장 실패 복구가 깨진다.
@Suite struct ContextReloadTests {
    private enum SaveFailure: Error { case diskUnavailable }

    private func diskContainer() throws -> ModelContainer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint-reload-\(UUID().uuidString)").appendingPathComponent("t.store")
        return try WaypointStore.makeContainer(url: url)
    }

    /// 다른 context의 저장은 이미 올라온 객체에 저절로 들어오지 않고, 그대로 저장하면 옛 값이 저장소를 덮는다.
    /// 다시 읽으면 값과 관계가 저장소대로 바뀌고, 그 뒤 저장해도 다른 context의 변경이 남는다.
    @Test func reloadPicksUpSiblingSave() throws {
        let container = try diskContainer()
        let main = ModelContext(container)
        let p = makeProject(main)
        let card = p.makeCard(in: main, title: "c", status: .next, at: t0)
        let s = makeSession(main, p, id: "S1")
        try main.save()
        #expect(card.cardSessions?.isEmpty == true && s.cardSessions?.isEmpty == true)

        let side = ModelContext(container)
        let sideCard = try #require(side.fetch(FetchDescriptor<Card>()).first)
        let sideSession = try #require(side.fetch(FetchDescriptor<Session>()).first)
        CardLifecycle.attach(sideCard, sideSession, at: t0 + 5, in: side)
        sideSession.lastSeenAt = t0 + 5
        try side.save()
        #expect(card.status == .next && card.cardSessions?.isEmpty == true)

        ContextReload.apply(main)
        #expect(card.status == .active && card.cardSessions?.count == 1)
        #expect(s.cardSessions?.count == 1 && s.lastSeenAt == t0 + 5)

        card.title = "고침"
        s.cachedState = .stalled
        try main.save()
        let check = ModelContext(container)
        let stored = try #require(check.fetch(FetchDescriptor<Card>()).first)
        let session = try #require(check.fetch(FetchDescriptor<Session>()).first)
        #expect(stored.status == .active && stored.title == "고침" && stored.cardSessions?.count == 1)
        #expect(session.lastSeenAt == t0 + 5)
    }

    /// 실시간 경로: 같은 context에서 저장에 실패한 훅을 다시 처리해도 잘못된 세션·연결이 생기지 않는다
    /// (`HookProcessor.handle`이 rollback 뒤 `ContextReload`).
    @Test func failedLiveSaveRetriedInSameContextLeavesNoStaleRecords() throws {
        let h = try HookHarness(onDisk: true)
        h.project.nextCardNumber = 16
        let card = h.project.makeCard(in: h.context, title: "파서 단위 테스트", status: .next, at: t0)
        try h.context.save()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PreToolUse-Agent", at: t0 + 10)
        h.processor.saveContext = { _ in throw SaveFailure.diskUnavailable }
        try h.send("doc-SubagentStart", at: t0 + 11)
        #expect(h.processor.lastSaveFailed)
        // 실패 직후 메모리 값이 저장소와 같다
        #expect(card.status == .next && card.cardSessions?.isEmpty == true)
        #expect(try h.session()?.children?.isEmpty == true)

        h.processor.saveContext = { try $0.save() }
        try h.send("doc-SubagentStart", at: t0 + 11)
        #expect(!h.processor.lastSaveFailed)
        let fresh = ModelContext(h.container)
        let ids = try fresh.fetch(FetchDescriptor<Session>()).map(\.id).sorted()
        #expect(ids == [HookHarness.agentID, HookHarness.sessionID].sorted())
        let links = try fresh.fetch(FetchDescriptor<CardSession>())
        #expect(links.count == 1 && links.first?.session?.id == HookHarness.agentID)
        #expect(card.status == .active)
    }
}
