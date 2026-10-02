import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 저장소 백업·복구(TRK-46). 모두 임시 폴더만 쓴다.
@Suite struct StoreBackupTests {
    let old = StoreVersionStamp(appVersion: "0.0.1", build: "1")
    let new = StoreVersionStamp(appVersion: "0.0.1", build: "2")

    // MARK: - upgrade·daily

    @Test func firstRunWithoutStoreMakesNoBackup() throws {
        let support = try StoreTemp()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.dir.path)
        let (_, outcome) = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        #expect(outcome.backups.isEmpty)
        #expect(support.launch(old).lastOpened() == old)
        #expect(try support.mode(support.dir) == 0o755)  // 저장 폴더 자체의 권한은 건드리지 않는다
    }

    @Test func existingStoreWithoutVersionFileIsUpgrade() throws {
        let support = try StoreTemp()
        try support.seed(["OLD"])
        let (_, outcome) = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        #expect(outcome.backups.map(\.info.reason) == [.upgrade])
        #expect(outcome.backups.first?.info.appVersion == "unknown")
        #expect(outcome.backups.first?.info.files["Waypoint.store"] != nil)
    }

    @Test func buildChangeMakesUpgradeBackupBeforeOpening() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        var opened = false
        let (_, outcome) = try support.launch(new).open(now: t0 + 60) { url -> ModelContainer in
            // 열기 전에 이미 떠 있어야 한다
            #expect(support.backup.list().first?.info.reason == .upgrade)
            opened = true
            return try WaypointStore.makeContainer(url: url)
        }
        #expect(opened)
        let entry = try #require(outcome.backups.first)
        #expect(entry.info.reason == .upgrade)
        #expect(entry.info.build == "1")  // 백업한 저장소를 마지막으로 연 앱
        #expect(entry.info.schemaVersion == "1.0.0")
        #expect(entry.info.method == .fileCopy)
        #expect(entry.id.hasSuffix("-upgrade"))
        #expect(support.launch(new).lastOpened() == new)
        #expect(try support.keys(in: entry) == ["LDG"])
    }

    @Test func sameVersionWithinADayMakesNoBackup() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        let (_, outcome) = try support.launch(old).open(now: t0 + 23 * 3600) { try WaypointStore.makeContainer(url: $0) }
        #expect(outcome.backups.isEmpty)
        #expect(support.backup.list().count == 1)
    }

    @Test func dailyBackupAfterADay() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        let (_, outcome) = try support.launch(old).open(now: t0 + 24 * 3600) { try WaypointStore.makeContainer(url: $0) }
        #expect(outcome.backups.map(\.info.reason) == [.daily])
        #expect(support.backup.isDailyDue(now: t0 + 25 * 3600) == false)
    }

    // MARK: - 유지·권한

    @Test func keepsOnlyRecentBackupsAndDropsUnfinished() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        var ids: [String] = []
        for i in 0..<10 {
            ids.append(try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0 + Double(i))).id)
        }
        // info.json 없는 폴더 = 끝나지 않은 백업
        let unfinished = support.backup.root.appendingPathComponent(StoreBackup.folderName(at: t0 - 100, reason: .daily))
        try FileManager.default.createDirectory(at: unfinished, withIntermediateDirectories: true)
        support.backup.prune()
        #expect(support.backup.list().map(\.id) == Array(ids.reversed().prefix(StoreBackup.keep)))
        #expect(!FileManager.default.fileExists(atPath: unfinished.path))
    }

    @Test func sameMillisecondKeepsOrder() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let a = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0))
        let b = try #require(try support.backup.copyClosedStore(reason: .upgrade, stamp: old, at: t0))
        #expect(support.backup.list().map(\.id) == [b.id, a.id])
    }

    @Test func permissionsArePrivate() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let entry = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0))
        #expect(try support.mode(support.backup.root) == 0o700)
        #expect(try support.mode(entry.url) == 0o700)
        let names = try FileManager.default.contentsOfDirectory(atPath: entry.url.path)
        #expect(names.contains("info.json") && names.contains("Waypoint.store"))
        for name in names {
            #expect(try support.mode(entry.url.appendingPathComponent(name)) == 0o600, "\(name)")
        }
        let online = try support.withOpenStore { _ in try support.backup.backupOpenStore(stamp: old, at: t0 + 1) }
        for name in try FileManager.default.contentsOfDirectory(atPath: online.url.path) {
            #expect(try support.mode(online.url.appendingPathComponent(name)) == 0o600, "\(name)")
        }
    }

    @Test func checkpointCachesAreNotBackedUp() throws {
        let support = try StoreTemp()
        try support.seed(["LDG"])
        let assets = support.dir.appendingPathComponent("Waypoint_ckAssets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: assets.appendingPathComponent("asset"))
        let entry = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0))
        let names = try FileManager.default.contentsOfDirectory(atPath: entry.url.path)
        #expect(!names.contains("Waypoint_ckAssets"))
        #expect(Set(names).isSubset(of: ["Waypoint.store", "Waypoint.store-wal", "Waypoint.store-shm", "info.json"]))
    }

    // MARK: - 열기 실패 복구

    /// 판이 바뀐 실행에서 저장소가 깨져 있으면, 열기 전 백업(깨진 사본)을 건너뛰고 그 앞의 정상 백업으로 되돌린다.
    @Test func brokenStoreIsMovedAsideAndRestored() throws {
        let support = try StoreTemp()
        try support.seed(["LDG", "WPT"])
        _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        let good = try #require(support.backup.list().first)
        let garbage = Data(repeating: 0x41, count: 16384)
        try support.corrupt(with: garbage)

        let (container, outcome) = try support.launch(new).open(now: t0 + 3600) { try WaypointStore.makeContainer(url: $0) }
        #expect(try support.keys(container) == ["LDG", "WPT"])
        let record = try #require(outcome.restore)
        #expect(record.kind == .automatic)
        #expect(record.backupID == good.id)
        #expect(outcome.backups.map(\.info.reason) == [.upgrade])  // 깨진 저장소의 사본(복원에 쓰지 않음)
        #expect(StoreRestoreRecord.load(supportDirectory: support.dir) == record)
        #expect(support.launch(new).lastOpened() == new)

        // 깨진 파일은 지우지 않고 옮겨 둔다
        let failed = support.dir.appendingPathComponent("store-failed").appendingPathComponent(try #require(record.failedFolder))
        #expect(try Data(contentsOf: failed.appendingPathComponent("Waypoint.store")) == garbage)
        #expect(FileManager.default.fileExists(atPath: failed.appendingPathComponent("failure.json").path))
        #expect(try support.mode(failed) == 0o700)
    }

    /// `quick_check`는 통과하지만 열리지 않는 백업(판이 안 맞는 경우 등)은 놓은 사본을 거두고 다음 백업으로 간다.
    @Test func backupThatPassesCheckButFailsToOpenIsSkipped() throws {
        let support = try StoreTemp()
        try support.seed(["OLD"])
        let older = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0))
        try support.seed(["NEW"])
        let newer = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0 + 1))
        try PrivateFile.write(try StoreBackup.encoder().encode(old), to: support.dir.appendingPathComponent(StoreLaunch.versionFileName))
        try support.corrupt(with: Data(repeating: 0x44, count: 8192))
        struct Mismatch: Error {}
        var calls = 0
        var placedOnSecondCall: [String] = []
        let (container, outcome) = try support.launch(old).open(now: t0 + 60) { url -> ModelContainer in
            calls += 1
            if calls == 1 { return try WaypointStore.makeContainer(url: url) }  // 깨진 저장소 → 실패
            if calls == 2 {
                placedOnSecondCall = try support.keys(in: StoreBackup.Entry(url: support.dir, info: newer.info))
                throw Mismatch()  // 최신 백업은 열리지 않는다고 친다
            }
            return try WaypointStore.makeContainer(url: url)
        }
        #expect(calls == 3)
        #expect(placedOnSecondCall == ["NEW", "OLD"])
        #expect(outcome.restore?.backupID == older.id)
        #expect(try support.keys(container) == ["OLD"])
    }

    @Test func withoutBackupFailureStaysAndFilesAreUntouched() throws {
        let support = try StoreTemp()
        let garbage = Data(repeating: 0x42, count: 8192)
        try garbage.write(to: support.store)
        // 판 기록이 같고 하루가 안 지났으면 열기 전 백업도 없다
        try PrivateFile.write(try StoreBackup.encoder().encode(old), to: support.dir.appendingPathComponent(StoreLaunch.versionFileName))
        try PrivateFile.makeDirectory(support.backup.root)
        #expect(throws: (any Error).self) {
            _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        }
        // 열기 전 daily 백업이 하나 생기지만 깨진 저장소의 사본이라 못 쓴다. 파일은 제자리로 돌아온다.
        #expect(support.backup.list().map(\.info.reason) == [.daily])
        #expect(try Data(contentsOf: support.store) == garbage)
        let failedRoot = support.dir.appendingPathComponent("store-failed")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: failedRoot.path)) ?? []).isEmpty)
        #expect(StoreRestoreRecord.load(supportDirectory: support.dir) == nil)
    }

    @Test func missingStoreFailureIsNotRecovered() throws {
        let support = try StoreTemp()
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            _ = try support.launch(old).open(now: t0) { _ -> Int in throw Boom() }
        }
        #expect(!FileManager.default.fileExists(atPath: support.dir.appendingPathComponent("store-failed").path))
    }

    /// 열린 상태에서 뜬 SQLite 백업(파일 하나)으로도 복구된다. 깨진 저장소의 -wal이 남아 붙지 않는다.
    @Test func recoversFromOnlineBackup() throws {
        let support = try StoreTemp()
        _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        let entry = try support.withOpenStore { container in
            let ctx = ModelContext(container)
            _ = makeProject(ctx, key: "ONL", name: "열린 채 백업")
            try ctx.save()
            return try support.backup.backupOpenStore(stamp: old, at: t0 + 10)
        }
        // 백업 뒤 기록(복원되면 사라져야 함)
        try support.withOpenStore { container in
            let ctx = ModelContext(container)
            _ = makeProject(ctx, key: "AFT", name: "백업 뒤")
            try ctx.save()
        }
        try support.corrupt(with: Data(repeating: 0x43, count: 16384), keepWAL: true)
        let (container, outcome) = try support.launch(old).open(now: t0 + 20) { try WaypointStore.makeContainer(url: $0) }
        #expect(outcome.restore?.backupID == entry.id)
        #expect(try support.keys(container) == ["ONL"])
    }

    // MARK: - SQLite 온라인 백업

    @Test func onlineBackupOfOpenStoreIsConsistentAndOpens() throws {
        let support = try StoreTemp()
        let entry = try support.withOpenStore { container in
            let ctx = ModelContext(container)
            for key in ["AAA", "BBB", "CCC"] { _ = makeProject(ctx, key: key, name: key) }
            try ctx.save()  // 아직 WAL에만 있다
            let entry = try support.backup.backupOpenStore(stamp: old, at: t0)
            // 백업 뒤에도 열린 저장소는 그대로 쓴다
            _ = makeProject(ctx, key: "DDD", name: "DDD")
            try ctx.save()
            return entry
        }
        #expect(entry.info.method == .sqliteBackup)
        #expect(entry.info.reason == .manual)
        let names = try FileManager.default.contentsOfDirectory(atPath: entry.url.path)
        #expect(Set(names) == ["Waypoint.store", "info.json"], "\(names)")
        let copy = entry.url.appendingPathComponent("Waypoint.store")
        #expect(SQLiteFile.quickCheck(copy))
        // 롤백 저널 모드(헤더 18·19바이트 = 1): -wal 없이 파일 하나로 열린다
        #expect(Array(try Data(contentsOf: copy).prefix(20).suffix(2)) == [1, 1])
        #expect(support.backup.isComplete(entry))
        #expect(try support.keys(in: entry) == ["AAA", "BBB", "CCC"])
    }

    // MARK: - 예약 복원

    @Test func scheduledRestoreRunsBeforeOpening() throws {
        let support = try StoreTemp()
        try support.seed(["AAA"])
        _ = try support.launch(old).open(now: t0) { try WaypointStore.makeContainer(url: $0) }
        let target = try #require(support.backup.list().first)
        try support.withOpenStore { container in
            let ctx = ModelContext(container)
            _ = makeProject(ctx, key: "BBB", name: "나중")
            try ctx.save()
        }
        try support.backup.scheduleRestore(target, at: t0 + 5)
        #expect(support.backup.scheduledRestore()?.backupID == target.id)

        let (container, outcome) = try support.launch(old).open(now: t0 + 10) { try WaypointStore.makeContainer(url: $0) }
        #expect(try support.keys(container) == ["AAA"])
        #expect(outcome.restore?.kind == .manual)
        #expect(outcome.restore?.backupID == target.id)
        #expect(support.backup.scheduledRestore() == nil)
        let before = try #require(outcome.backups.first)
        #expect(before.info.reason == .beforeRestore)
        #expect(try support.keys(in: before) == ["AAA", "BBB"])
        #expect(support.backup.list().map(\.id).contains(target.id))
    }

    @Test func scheduledRestoreSurvivesPruning() throws {
        let support = try StoreTemp()
        try support.seed(["AAA"])
        let target = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0))
        for i in 1..<StoreBackup.keep { _ = try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0 + Double(i)) }
        try support.backup.scheduleRestore(target)
        let (_, outcome) = try support.launch(old).open(now: t0 + 100) { try WaypointStore.makeContainer(url: $0) }
        #expect(outcome.restore?.backupID == target.id)
        #expect(support.backup.list().map(\.id).contains(target.id))
    }

    @Test func scheduledRestoreOfMissingBackupLeavesStore() throws {
        let support = try StoreTemp()
        try support.seed(["AAA"])
        let entry = try #require(try support.backup.copyClosedStore(reason: .daily, stamp: old, at: t0))
        try support.backup.scheduleRestore(entry)
        try FileManager.default.removeItem(at: entry.url)
        let (container, outcome) = try support.launch(old).open(now: t0 + 10) { try WaypointStore.makeContainer(url: $0) }
        #expect(try support.keys(container) == ["AAA"])
        #expect(outcome.restore == nil)
        #expect(outcome.notes.contains { $0.hasPrefix("예약한 백업 없음") })
        #expect(support.backup.scheduledRestore() == nil)
    }
}

/// 임시 저장 폴더 하나.
struct StoreTemp {
    let dir: URL
    var store: URL { dir.appendingPathComponent("Waypoint.store") }
    var backup: StoreBackup { StoreBackup(storeURL: store) }

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func launch(_ stamp: StoreVersionStamp) -> StoreLaunch { StoreLaunch(storeURL: store, stamp: stamp) }

    /// 저장소를 열어 `body`를 돌리고 닫는다.
    func withOpenStore<T>(_ body: (ModelContainer) throws -> T) throws -> T {
        let container = try WaypointStore.makeContainer(url: store)
        return try body(container)
    }

    func seed(_ keys: [String]) throws {
        try withOpenStore { container in
            let ctx = ModelContext(container)
            for key in keys { _ = makeProject(ctx, key: key, name: key) }
            try ctx.save()
        }
    }

    func keys(_ container: ModelContainer) throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<Project>()).map(\.key).sorted()
    }

    /// 백업 사본을 다른 임시 폴더에 놓고 열어 프로젝트 키를 읽는다(백업 폴더는 바꾸지 않는다).
    func keys(in entry: StoreBackup.Entry) throws -> [String] {
        let other = try StoreTemp()
        try StoreBackup(storeURL: other.store).place(entry)
        return try other.withOpenStore { try other.keys($0) }
    }

    /// 저장소 본 파일을 `data`로 덮어쓴다. `keepWAL`이 아니면 -wal·-shm도 지운다.
    func corrupt(with data: Data, keepWAL: Bool = false) throws {
        try data.write(to: store)
        if !keepWAL {
            for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: store.path + suffix) }
        }
    }

    func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
