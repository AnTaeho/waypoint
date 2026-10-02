import Foundation
import SwiftData

/// 이 저장소를 마지막으로 연 앱 버전·빌드·저장 형식 판. 다르면 열기 전에 `upgrade` 백업을 뜬다.
public struct StoreVersionStamp: Codable, Equatable, Sendable {
    public var appVersion: String
    public var build: String
    public var schemaVersion: String

    public init(appVersion: String, build: String, schemaVersion: String = WaypointStore.currentSchemaVersion) {
        self.appVersion = appVersion
        self.build = build
        self.schemaVersion = schemaVersion
    }

    /// `store-version.json`이 없는 저장소(TRK-46 이전 앱이 연 것). 그때 모델은 1판과 같다.
    public static let beforeTracking = StoreVersionStamp(appVersion: "unknown", build: "unknown", schemaVersion: "1.0.0")

    /// 지금 도는 앱(번들이 없으면 「unknown」).
    public static func current(bundle: Bundle = .main) -> StoreVersionStamp {
        StoreVersionStamp(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        )
    }
}

/// 백업으로 저장소를 되돌린 기록(`store-restore.json`). 화면이 알리고 사람이 확인하면 지운다.
public struct StoreRestoreRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 저장소를 열지 못해 저절로
        case automatic
        /// 예약한 복원
        case manual
    }

    public var kind: Kind
    /// 되돌린 시각
    public var at: Date
    /// 쓴 백업 폴더 이름과 그 백업을 뜬 시각
    public var backupID: String
    public var backupCreatedAt: Date
    /// 열지 못한 저장소를 옮겨 둔 폴더(`automatic`만)
    public var failedFolder: String?
    /// 열지 못한 원인(`automatic`만)
    public var failure: String?

    public static let fileName = "store-restore.json"

    public static func load(supportDirectory: URL) -> StoreRestoreRecord? {
        guard let data = try? Data(contentsOf: supportDirectory.appendingPathComponent(fileName)) else { return nil }
        return try? StoreBackup.decoder().decode(StoreRestoreRecord.self, from: data)
    }

    public static func clear(supportDirectory: URL) {
        try? FileManager.default.removeItem(at: supportDirectory.appendingPathComponent(fileName))
    }

    func save(supportDirectory: URL) throws {
        try PrivateFile.write(try StoreBackup.encoder().encode(self), to: supportDirectory.appendingPathComponent(Self.fileName))
    }
}

/// 다음 실행 때 되돌릴 백업(`pending-restore.json`). 열린 저장소를 바꿔 끼우지 않으려고 예약만 한다.
public struct StoreRestoreRequest: Codable, Equatable, Sendable {
    public var backupID: String
    public var requestedAt: Date

    public static let fileName = "pending-restore.json"
}

extension StoreBackup {
    /// `entry`를 다음 실행 때 되돌리도록 적어 둔다(이미 있으면 바꾼다).
    public func scheduleRestore(_ entry: Entry, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let request = StoreRestoreRequest(backupID: entry.id, requestedAt: date)
        try PrivateFile.write(try Self.encoder().encode(request), to: pendingRestoreURL)
    }

    public func scheduledRestore() -> StoreRestoreRequest? {
        guard let data = try? Data(contentsOf: pendingRestoreURL) else { return nil }
        return try? Self.decoder().decode(StoreRestoreRequest.self, from: data)
    }

    public func cancelScheduledRestore() {
        try? FileManager.default.removeItem(at: pendingRestoreURL)
    }

    var pendingRestoreURL: URL { supportDirectory.appendingPathComponent(StoreRestoreRequest.fileName) }
}

/// 실행할 때 저장소를 여는 순서(TRK-46): 예약 복원 → `upgrade`/`daily` 백업 → 열기 → 실패하면 복구.
///
/// 복구: 열지 못한 저장소 파일을 `<저장 폴더>/store-failed/<시각>/`으로 옮겨 두고(지우지 않는다), 백업을 최신순으로
/// 하나씩 저장소 자리에 놓아 `quick_check`·열기를 해 본다. 열리면 `store-restore.json`을 남긴다.
/// 하나도 안 되면 옮긴 파일을 제자리로 돌려놓고 처음 오류를 던진다.
public struct StoreLaunch: Sendable {
    public static let versionFileName = "store-version.json"
    public static let failedFolderName = "store-failed"

    public let backup: StoreBackup
    public let stamp: StoreVersionStamp

    public init(storeURL: URL, stamp: StoreVersionStamp) {
        backup = StoreBackup(storeURL: storeURL)
        self.stamp = stamp
    }

    public var storeURL: URL { backup.storeURL }
    var supportDirectory: URL { backup.supportDirectory }
    var versionURL: URL { supportDirectory.appendingPathComponent(Self.versionFileName) }

    /// 이번 실행에서 한 일.
    public struct Outcome: Sendable {
        /// 뜬 백업(열기 전)
        public var backups: [StoreBackup.Entry] = []
        /// 되돌렸으면 그 기록
        public var restore: StoreRestoreRecord?
        /// 막지 않은 문제(백업 실패, 없는 예약 백업 등)
        public var notes: [String] = []
    }

    /// 지난번 연 판. 없으면 nil(처음 실행이거나 TRK-46 이전 앱이 열었던 저장소).
    public func lastOpened() -> StoreVersionStamp? {
        guard let data = try? Data(contentsOf: versionURL) else { return nil }
        return try? StoreBackup.decoder().decode(StoreVersionStamp.self, from: data)
    }

    /// - Parameter open: 저장소를 연다(앱은 `WaypointStore.makeContainer`). 실패하면 던진다.
    public func open<Container>(now: Date = Date(), _ open: (URL) throws -> Container) throws -> (Container, Outcome) {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        var outcome = Outcome()
        let restored = applyScheduledRestore(now: now, outcome: &outcome)
        if !restored { backupBeforeOpening(now: now, outcome: &outcome) }

        let firstError: Error
        do {
            let container = try open(storeURL)
            recordOpened(now: now, outcome: &outcome)
            return (container, outcome)
        } catch {
            firstError = error
        }
        // 저장소가 없는데 못 열었으면 저장소 탓이 아니다(폴더 권한 등). 되돌릴 것도 없다.
        guard backup.storeExists else { throw firstError }
        let container = try recover(from: firstError, now: now, outcome: &outcome, open)
        recordOpened(now: now, outcome: &outcome)
        return (container, outcome)
    }

    // MARK: - 열기 전

    /// 예약 복원: 지금 저장소를 `beforeRestore` 백업으로 옮기고 예약한 백업을 놓는다. 되돌렸으면 true.
    /// 어느 단계든 실패하면 지금 저장소를 제자리로 돌려놓고 예약을 지운다(다음 실행에서 되풀이하지 않게).
    private func applyScheduledRestore(now: Date, outcome: inout Outcome) -> Bool {
        guard let request = backup.scheduledRestore() else { return false }
        backup.cancelScheduledRestore()
        guard let target = backup.list().first(where: { $0.id == request.backupID }), backup.isComplete(target) else {
            outcome.notes.append("예약한 백업 없음 · \(request.backupID)")
            return false
        }
        var moved: StoreBackup.Entry?
        do {
            moved = try backup.moveClosedStore(reason: .beforeRestore, stamp: lastOpened() ?? .beforeTracking, at: now)
            try backup.place(target)
            let record = StoreRestoreRecord(kind: .manual, at: now, backupID: target.id,
                                            backupCreatedAt: target.info.createdAt)
            try? record.save(supportDirectory: supportDirectory)
            outcome.restore = record
            if let moved { outcome.backups.append(moved) }
            backup.prune(protecting: Set([moved?.id, target.id].compactMap { $0 }))
            return true
        } catch {
            outcome.notes.append("예약 복원 실패 · \(error)")
            backup.removePlacedCopies()
            if let moved, putBack(from: moved.url) {
                try? FileManager.default.removeItem(at: moved.url)
            }
            return false
        }
    }

    /// 판이 바뀌었으면 `upgrade`, 마지막 백업이 하루 넘었으면 `daily`. 실패해도 열기는 막지 않는다.
    private func backupBeforeOpening(now: Date, outcome: inout Outcome) {
        guard backup.storeExists else { return }
        let reason: StoreBackup.Reason?
        if lastOpened() != stamp {
            reason = .upgrade
        } else if backup.isDailyDue(now: now) {
            reason = .daily
        } else {
            reason = nil
        }
        guard let reason else { return }
        do {
            if let entry = try backup.copyClosedStore(reason: reason, stamp: lastOpened() ?? .beforeTracking, at: now) {
                outcome.backups.append(entry)
            }
            backup.prune()
        } catch {
            outcome.notes.append("\(reason.rawValue) 백업 실패 · \(error)")
        }
    }

    private func recordOpened(now: Date, outcome: inout Outcome) {
        do {
            try PrivateFile.write(try StoreBackup.encoder().encode(stamp), to: versionURL)
        } catch {
            outcome.notes.append("판 기록 실패 · \(error)")
        }
    }

    // MARK: - 복구

    private func recover<Container>(
        from firstError: Error, now: Date, outcome: inout Outcome, _ open: (URL) throws -> Container
    ) throws -> Container {
        guard let failed = try? moveAside(error: firstError, now: now) else { throw firstError }
        for candidate in backup.list() where backup.isComplete(candidate) {
            do {
                try backup.place(candidate)
                guard SQLiteFile.quickCheck(storeURL) else {
                    backup.removePlacedCopies()
                    continue
                }
                let container = try open(storeURL)
                let record = StoreRestoreRecord(
                    kind: .automatic, at: now, backupID: candidate.id, backupCreatedAt: candidate.info.createdAt,
                    failedFolder: failed.lastPathComponent, failure: String(describing: firstError)
                )
                try? record.save(supportDirectory: supportDirectory)
                outcome.restore = record
                return container
            } catch {
                backup.removePlacedCopies()
            }
        }
        // 되돌릴 백업이 없다: 처음 모습으로 돌려놓고 원인을 그대로 알린다.
        if putBack(from: failed) {
            try? FileManager.default.removeItem(at: failed)
        }
        throw firstError
    }

    /// 열지 못한 저장소 파일을 `store-failed/<시각>/`으로 옮기고 원인을 `failure.json`에 남긴다.
    private func moveAside(error: Error, now: Date) throws -> URL {
        let root = supportDirectory.appendingPathComponent(Self.failedFolderName, isDirectory: true)
        try PrivateFile.makeDirectory(root)
        let name = StoreBackup.timestamp(now)
        var folder = root.appendingPathComponent(name, isDirectory: true)
        var suffix = 1
        while FileManager.default.fileExists(atPath: folder.path) {
            suffix += 1
            folder = root.appendingPathComponent("\(name)_\(suffix)", isDirectory: true)
        }
        try PrivateFile.makeDirectory(folder)
        let intact = SQLiteFile.quickCheck(storeURL)
        for file in StoreBackup.storeFiles(of: storeURL) where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        let failure: [String: String] = [
            "at": ISO8601DateFormatter().string(from: now),
            "error": String(describing: error),
            "quickCheck": intact ? "ok" : "failed",
        ]
        try? PrivateFile.write(try JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys]),
                               to: folder.appendingPathComponent("failure.json"))
        return folder
    }

    /// `folder`에 옮겨 둔 저장소 파일을 제자리로 돌려놓는다(자리가 비어 있을 때만). 모두 옮겼으면 true.
    @discardableResult
    private func putBack(from folder: URL) -> Bool {
        let fm = FileManager.default
        guard !StoreBackup.storeFiles(of: storeURL).contains(where: { fm.fileExists(atPath: $0.path) }) else { return false }
        var all = true
        for file in StoreBackup.storeFiles(of: storeURL) {
            let source = folder.appendingPathComponent(file.lastPathComponent)
            guard fm.fileExists(atPath: source.path) else { continue }
            do { try fm.moveItem(at: source, to: file) } catch { all = false }
        }
        return all
    }
}

public extension WaypointStore {
    /// 앱 실행용: 예약 복원·열기 전 백업·열기·복구(`StoreLaunch`)를 거쳐 저장소를 연다.
    static func openForLaunch(
        url: URL, cloudKitContainer: String?, stamp: StoreVersionStamp = .current()
    ) throws -> (ModelContainer, StoreLaunch.Outcome) {
        try StoreLaunch(storeURL: url, stamp: stamp).open { try makeContainer(url: $0, cloudKitContainer: cloudKitContainer) }
    }
}
