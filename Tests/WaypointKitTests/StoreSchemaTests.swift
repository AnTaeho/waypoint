import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 판 고정(TRK-46): 판을 붙이기 전 모델로 만든 저장소가 그대로 열려야 한다.
@Suite struct StoreSchemaTests {
    @Test func currentVersionIsOne() {
        #expect(WaypointStore.currentSchemaVersion == "1.0.0")
        #expect(WaypointMigrationPlan.stages.isEmpty)
        #expect(WaypointStore.schema.entities.count == WaypointSchemaV1.models.count)
    }

    /// 판 없는 `Schema([...])`로 만든 저장소를 V1 + 옮기기 계획으로 연다.
    @Test func unversionedStoreOpensAsV1() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Waypoint.store")
        try {
            let legacy = Schema([
                Project.self, Card.self, Session.self, CardSession.self, Event.self, GuideDoc.self, GuideVersion.self,
            ])
            let config = ModelConfiguration(schema: legacy, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: legacy, configurations: [config])
            let ctx = ModelContext(container)
            let project = makeProject(ctx, key: "OLD", name: "옛 저장소")
            project.makeCard(in: ctx, title: "남아 있어야 할 카드", at: t0)
            try ctx.save()
        }()

        let container = try WaypointStore.makeContainer(url: url)
        let ctx = ModelContext(container)
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projects.map(\.key) == ["OLD"])
        #expect(try ctx.fetch(FetchDescriptor<Card>()).map(\.title) == ["남아 있어야 할 카드"])
    }

    /// 이 Mac의 실제 저장소 **사본**을 연다. `WAYPOINT_REAL_STORE_COPY`(사본 `.store` 경로)가 있을 때만 돈다.
    /// 사본은 테스트가 다시 한 번 임시 폴더로 복사해 연다(넘겨준 사본도 바꾸지 않게).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"] != nil))
    func realStoreCopyOpensAsV1() throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Waypoint.store")
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let container = try WaypointStore.makeContainer(url: url)
        let ctx = ModelContext(container)
        let cards = try ctx.fetchCount(FetchDescriptor<Card>())
        let events = try ctx.fetchCount(FetchDescriptor<Event>())
        print("[real-store-copy] projects=\(try ctx.fetchCount(FetchDescriptor<Project>())) cards=\(cards) events=\(events)")
        #expect(cards > 0)
    }
}
