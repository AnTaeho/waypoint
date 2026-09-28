import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct SampleDataTests {
    let now = t0 + 7 * 24 * 3600

    @Test func seedsOnlyOnce() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        #expect(try SampleData.seedIfEmpty(ctx, now: now) == true)
        let cards = try ctx.fetchCount(FetchDescriptor<Card>())
        #expect(try SampleData.seedIfEmpty(ctx, now: now) == false)
        #expect(try ctx.fetchCount(FetchDescriptor<Project>()) == 4)
        #expect(try ctx.fetchCount(FetchDescriptor<Card>()) == cards)
    }

    @Test func dashboardMatchesDesign() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        try SampleData.seedIfEmpty(ctx, now: now)
        let groups = try DashboardQuery.groups(in: ctx, now: now)
        #expect(groups.map(\.project.key) == ["LDG", "WEB", "TRK"])

        let ldg = try #require(groups.first { $0.project.key == "LDG" })
        #expect(ldg.rows.map(\.card?.displayID) == ["LDG-14", "LDG-16"])
        #expect(ldg.rows.map(\.depth) == [0, 1])
        #expect(ldg.rows.allSatisfy { $0.workState == .live })
        #expect(ldg.rows[1].session.agentName == "test-writer")
        #expect(ldg.rows[0].session.id.hasPrefix("7f2a"))
        // 시안의 최근 파일. 같은 시각 이벤트가 있으면 실행마다 바뀌던 문제의 회귀 방지.
        #expect(SessionFormat.recentFileName(card: try #require(ldg.rows[0].card), session: ldg.rows[0].session) == "ReceiptParser.swift")

        let trk = try #require(groups.first { $0.project.key == "TRK" })
        #expect(trk.rows.count == 1)
        #expect(trk.rows.first?.workState == .stalled)
        #expect(trk.rows.first?.card?.displayID == "TRK-3")
    }

    @Test func projectTableMatchesDesign() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        try SampleData.seedIfEmpty(ctx, now: now)
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        func s(_ key: String) throws -> ProjectSummary {
            DashboardQuery.summary(for: try #require(projects.first { $0.key == key }), now: now)
        }
        // 작업중(live) / 다음 / 아이디어
        let expected: [String: (Int, Int, Int)] = ["LDG": (2, 4, 6), "WEB": (1, 2, 3), "TRK": (0, 3, 9), "PIX": (0, 1, 0)]
        for (key, e) in expected {
            let sum = try s(key)
            #expect(sum.liveCount == e.0, "\(key) live")
            #expect(sum.nextCount == e.1, "\(key) next")
            #expect(sum.ideaCount == e.2, "\(key) idea")
        }
        #expect(try s("TRK").stalledCount == 1)
        #expect(try s("LDG").lastActivityAt == now)
        #expect(try s("TRK").lastActivityAt == now - 22 * 60)
        #expect(try s("PIX").lastActivityAt == now - 3 * 24 * 3600)
    }

    @Test func ledgerCardsAreConsistent() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        try SampleData.seedIfEmpty(ctx, now: now)
        let ldg = try #require(try ctx.fetch(FetchDescriptor<Project>()).first { $0.key == "LDG" })
        let cards = ldg.cards ?? []
        #expect(ldg.nextCardNumber == (cards.map(\.number).max() ?? 0) + 1)
        #expect(Set(cards.map(\.number)).count == cards.count)

        let c14 = try #require(cards.first { $0.number == 14 })
        #expect(c14.status == .active)
        #expect(c14.statusBeforeActive == "next")
        #expect(c14.criteria.count == 4)
        #expect(c14.doneCriteriaCount == 2)
        #expect(c14.nextSessionNote != nil)
        #expect(c14.openCardSessions.first?.session?.gitBranch == "feat/ocr-mapping")
        let c16 = try #require(cards.first { $0.number == 16 })
        #expect(c16.parent === c14)

        let recentDone = cards.filter { $0.status == .done && ($0.doneAt ?? .distantPast) > now - 7 * 24 * 3600 }
        #expect(Set(recentDone.map(\.number)) == [10, 11, 13])
        // 끝난 카드에 열린 연결이 남지 않는다
        #expect(cards.filter { $0.status != .active }.allSatisfy { $0.openCardSessions.isEmpty })

        let files = (c14.events ?? []).filter { $0.type == .fileChanged }
        #expect(files.contains { $0.payloadValues["path"]?.stringValue == "Ledger/OCR/ReceiptParser.swift"
            && $0.payloadValues["added"]?.intValue == 84 })
    }
}

@Suite struct StoreTests {
    @Test func cascadeDeleteFromProject() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        try SampleData.seedIfEmpty(ctx, now: t0)
        for p in try ctx.fetch(FetchDescriptor<Project>()) { ctx.delete(p) }
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<CardSession>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<GuideDoc>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<GuideVersion>()) == 0)
    }

    @Test func fileStoreAtGivenURL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Test.store")
        do {
            let container = try WaypointStore.makeContainer(inMemory: false, url: url)
            let ctx = ModelContext(container)
            ctx.insert(Project(key: "AAA", name: "a"))
            try ctx.save()
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let again = ModelContext(try WaypointStore.makeContainer(inMemory: false, url: url))
        #expect(try again.fetchCount(FetchDescriptor<Project>()) == 1)
    }

    @Test func defaultURLs() throws {
        // create: false — 테스트가 실제 Application Support 폴더를 만들지 않게
        #expect(try WaypointStore.defaultStoreURL(create: false).lastPathComponent == "Waypoint.store")
        #expect(try WaypointStore.sampleStoreURL(create: false).lastPathComponent == "Sample.store")
        #expect(try WaypointStore.defaultStoreURL(create: false).deletingLastPathComponent().lastPathComponent == "Waypoint")
    }
}
