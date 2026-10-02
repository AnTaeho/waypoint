import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 떠 있는 동안의 daily 백업(TRK-46).
@Suite struct StoreDailyBackupTests {
    let stamp = StoreVersionStamp(appVersion: "0.0.1", build: "1")

    @Test func dueOnlyAfterTwentyFourHours() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let first = try #require(try support.backup.copyClosedStore(reason: .upgrade, stamp: stamp, at: t0))
        let daily = StoreDailyBackup(storeURL: support.store, stamp: stamp)
        try support.withOpenStore { _ in
            #expect(try daily.runIfDue(now: t0 + StoreBackup.dailyInterval - 1) == nil)
            let entry = try #require(try daily.runIfDue(now: t0 + StoreBackup.dailyInterval))
            #expect(entry.info.reason == .daily)
            #expect(entry.info.method == .sqliteBackup)
            #expect(try daily.runIfDue(now: t0 + StoreBackup.dailyInterval + 3600) == nil)
        }
        #expect(support.backup.list().map(\.id).last == first.id)
        #expect(try support.keys(in: try #require(support.backup.list().first)) == ["LDG"])
    }

    @Test func noBackupsMeansDue() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let daily = StoreDailyBackup(storeURL: support.store, stamp: stamp)
        let entry = try support.withOpenStore { _ in try daily.runIfDue(now: t0) }
        #expect(entry?.info.reason == .daily)
    }

    @Test func secondClaimWhileRunningIsRefused() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let daily = StoreDailyBackup(storeURL: support.store, stamp: stamp)
        #expect(daily.claim(now: t0))
        #expect(!daily.claim(now: t0 + 1))  // 진행 중
        daily.finish(nil)  // 실패로 끝남 → 다음 점검에서 다시
        #expect(daily.claim(now: t0 + 10))
        daily.finish(nil)
    }

    @Test func failureRetriesNextTime() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let daily = StoreDailyBackup(storeURL: support.store, stamp: stamp)
        // 백업 폴더 자리에 파일을 두어 백업을 실패시킨다
        try Data().write(to: support.backup.root)
        #expect(throws: (any Error).self) { try daily.runIfDue(now: t0) }
        try FileManager.default.removeItem(at: support.backup.root)
        let entry = try support.withOpenStore { _ in try daily.runIfDue(now: t0 + 10) }
        #expect(entry?.info.reason == .daily)
    }

    @Test func startIfDueRunsInBackgroundOnce() async throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let daily = StoreDailyBackup(storeURL: support.store, stamp: stamp)
        let container = try WaypointStore.makeContainer(url: support.store)
        #expect(daily.startIfDue(now: t0))
        #expect(!daily.startIfDue(now: t0 + 1))
        for _ in 0..<100 where support.backup.list().isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(support.backup.list().map(\.info.reason) == [.daily])
        _ = container
    }
}
