import Foundation

/// 저장소(`Waypoint.store`) 백업(TRK-46). 이 Mac에만 둔다(SwiftData·CloudKit에 넣지 않는다).
///
/// 자리: `<저장 폴더>/store-backups/<UTC 시각 yyyyMMddTHHmmss.SSSZ>-<사유>/`에 저장소 파일과 `info.json`.
/// 폴더 0700, 파일 0600. 최근 `keep`개만 남긴다. `info.json`은 마지막에 써서, 없으면 끝나지 않은 백업으로 본다.
/// `Waypoint_ckAssets/`(동기화가 내려받는 첨부 캐시)는 넣지 않는다.
public struct StoreBackup: Sendable {

    public enum Reason: String, Codable, Sendable, CaseIterable {
        /// 앱 버전·빌드나 저장 형식 판이 지난번 연 것과 다를 때(열기 전)
        case upgrade
        /// 마지막 백업이 24시간보다 오래됐을 때(열기 전)
        case daily
        /// 사람이 고른 때(열린 상태)
        case manual
        /// 예약한 복원 바로 전(열기 전)
        case beforeRestore
        /// 모든 기록 지우기 바로 전(열린 상태, TRK-47). 이 값을 모르는 옛 앱은 이 백업을 목록·정리에서 건너뛴다.
        case beforeDelete
    }

    /// 뜬 방법. 열기 전에는 파일 복사(store·-wal·-shm), 열린 상태에서는 SQLite 온라인 백업(파일 하나).
    public enum Method: String, Codable, Sendable {
        case fileCopy
        case sqliteBackup
    }

    public struct Info: Codable, Hashable, Sendable {
        public var reason: Reason
        public var createdAt: Date
        /// 앱 버전·빌드·판: 이 백업의 저장소를 마지막으로 연 앱(열기 전 백업이면 지난번 실행, `manual`이면 지금 앱).
        public var appVersion: String
        public var build: String
        public var schemaVersion: String
        public var method: Method
        /// 파일 이름 → 바이트
        public var files: [String: Int64]
    }

    public struct Entry: Identifiable, Hashable, Sendable {
        /// 폴더 이름
        public var id: String { url.lastPathComponent }
        public var url: URL
        public var info: Info
    }

    public static let folderName = "store-backups"
    public static let infoName = "info.json"
    /// 남기는 백업 수. 실제 저장소가 30 MB 안팎이라 7개면 200 MB 남짓.
    public static let keep = 7
    /// `daily` 간격
    public static let dailyInterval: TimeInterval = 24 * 60 * 60

    public let storeURL: URL

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    public var supportDirectory: URL { storeURL.deletingLastPathComponent() }
    public var root: URL { supportDirectory.appendingPathComponent(Self.folderName, isDirectory: true) }

    /// 저장소를 이루는 파일(본 파일, -wal, -shm). 첨부 캐시 폴더는 넣지 않는다.
    public static func storeFiles(of storeURL: URL) -> [URL] {
        ["", "-wal", "-shm"].map { URL(fileURLWithPath: storeURL.path + $0) }
    }

    public var storeExists: Bool { FileManager.default.fileExists(atPath: storeURL.path) }

    // MARK: - 읽기

    /// 끝난 백업(최신순).
    public func list() -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { Self.parse($0) != nil }.sorted().reversed().compactMap { name in
            let url = root.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: url.appendingPathComponent(Self.infoName)),
                  let info = try? Self.decoder().decode(Info.self, from: data) else { return nil }
            return Entry(url: url, info: info)
        }
    }

    /// 마지막 백업이 `dailyInterval`보다 오래됐거나 없으면 true.
    public func isDailyDue(now: Date) -> Bool {
        guard let last = list().first?.info.createdAt else { return true }
        return now.timeIntervalSince(last) >= Self.dailyInterval
    }

    // MARK: - 쓰기

    /// 닫힌 저장소를 파일 복사로 뜬다(컨테이너를 열기 전). 저장소가 없으면 nil.
    @discardableResult
    public func copyClosedStore(reason: Reason, stamp: StoreVersionStamp, at date: Date) throws -> Entry? {
        guard storeExists else { return nil }
        let folder = try makeFolder(reason: reason, at: date)
        var sizes: [String: Int64] = [:]
        for file in Self.storeFiles(of: storeURL) where FileManager.default.fileExists(atPath: file.path) {
            let target = folder.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: file, to: target)
            try PrivateFile.restrict(target)
            sizes[file.lastPathComponent] = try PrivateFile.size(target)
        }
        return try finish(folder, reason: reason, stamp: stamp, at: date, method: .fileCopy, files: sizes)
    }

    /// 닫힌 저장소 파일을 백업 폴더로 **옮긴다**(복사하지 않는다). 예약 복원이 지금 저장소를 비킬 때 쓴다.
    @discardableResult
    func moveClosedStore(reason: Reason, stamp: StoreVersionStamp, at date: Date) throws -> Entry? {
        guard storeExists else { return nil }
        let folder = try makeFolder(reason: reason, at: date)
        var sizes: [String: Int64] = [:]
        for file in Self.storeFiles(of: storeURL) where FileManager.default.fileExists(atPath: file.path) {
            let target = folder.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.moveItem(at: file, to: target)
            try PrivateFile.restrict(target)
            sizes[file.lastPathComponent] = try PrivateFile.size(target)
        }
        return try finish(folder, reason: reason, stamp: stamp, at: date, method: .fileCopy, files: sizes)
    }

    /// 열린 저장소를 SQLite 온라인 백업으로 뜬다. 앱이 쓰는 중이어도 한 시점의 일관된 사본이 된다.
    @discardableResult
    public func backupOpenStore(reason: Reason = .manual, stamp: StoreVersionStamp, at date: Date) throws -> Entry {
        let folder = try makeFolder(reason: reason, at: date)
        let target = folder.appendingPathComponent(storeURL.lastPathComponent)
        // 0600으로 먼저 만들어 둔다(SQLite가 umask로 만들지 않게).
        try PrivateFile.write(Data(), to: target)
        try SQLiteFile.onlineBackup(from: storeURL, to: target)
        // 롤백 저널로 바꾼 뒤 닫으면 -shm 빈 껍데기만 남는다(-wal 내용은 이미 본 파일에 들어갔다).
        try? FileManager.default.removeItem(atPath: target.path + "-shm")
        var sizes: [String: Int64] = [:]
        for file in Self.storeFiles(of: target) where FileManager.default.fileExists(atPath: file.path) {
            try PrivateFile.restrict(file)
            sizes[file.lastPathComponent] = try PrivateFile.size(file)
        }
        let entry = try finish(folder, reason: reason, stamp: stamp, at: date, method: .sqliteBackup, files: sizes)
        prune()
        return entry
    }

    /// 최근 `keep`개(와 `protecting`)만 남기고 지운다. `info.json`이 없는 폴더(끝나지 않은 백업)도 지운다.
    public func prune(keep: Int = StoreBackup.keep, protecting: Set<String> = []) {
        let fm = FileManager.default
        let valid = list()
        let kept = Set(valid.prefix(keep).map(\.id)).union(protecting)
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where Self.parse(name) != nil && !kept.contains(name) {
            try? fm.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    // MARK: - 복원 자리 놓기

    /// 백업 파일을 저장소 자리에 복사한다. 저장소 자리에는 store·-wal·-shm 어느 것도 없어야 한다
    /// (남은 -wal이 다른 저장소 파일에 붙으면 조용히 깨진다).
    func place(_ entry: Entry) throws {
        let fm = FileManager.default
        if let leftover = Self.storeFiles(of: storeURL).first(where: { fm.fileExists(atPath: $0.path) }) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: leftover.path])
        }
        let base = storeURL.lastPathComponent
        for name in entry.info.files.keys.sorted() {
            guard name.hasPrefix(base) else { continue }
            let target = supportDirectory.appendingPathComponent(name)
            try fm.copyItem(at: entry.url.appendingPathComponent(name), to: target)
            try PrivateFile.restrict(target)
        }
    }

    /// 저장소 자리의 파일(store·-wal·-shm)을 지운다. 백업에서 복사해 놓은 사본을 거둘 때만 쓴다.
    func removePlacedCopies() {
        for file in Self.storeFiles(of: storeURL) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// 백업 파일 크기가 `info.json`과 같은가(복사 도중 잘린 백업을 거른다).
    func isComplete(_ entry: Entry) -> Bool {
        entry.info.files[storeURL.lastPathComponent] != nil && entry.info.files.allSatisfy { name, size in
            (try? PrivateFile.size(entry.url.appendingPathComponent(name))) == size
        }
    }

    // MARK: - 내부

    private func makeFolder(reason: Reason, at date: Date) throws -> URL {
        try PrivateFile.makeDirectory(root)
        // 같은 밀리초(또는 더 늦은 시각)의 폴더가 있으면 1 ms씩 뒤로 밀어 이름 순서 = 뜬 순서를 지킨다.
        var millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).compactMap(Self.parse)
        if let last = names.map(\.at).max() {
            millis = max(millis, Int64((last.timeIntervalSince1970 * 1000).rounded()) + 1)
        }
        let stamp = Date(timeIntervalSince1970: Double(millis) / 1000)
        let folder = root.appendingPathComponent(Self.folderName(at: stamp, reason: reason), isDirectory: true)
        try PrivateFile.makeDirectory(folder)
        return folder
    }

    private func finish(
        _ folder: URL, reason: Reason, stamp: StoreVersionStamp, at date: Date, method: Method, files: [String: Int64]
    ) throws -> Entry {
        let info = Info(reason: reason, createdAt: date, appVersion: stamp.appVersion, build: stamp.build,
                        schemaVersion: stamp.schemaVersion, method: method, files: files)
        try PrivateFile.write(try Self.encoder().encode(info), to: folder.appendingPathComponent(Self.infoName))
        return Entry(url: folder, info: info)
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter
    }

    /// `20261002T153012.123Z`(UTC, 밀리초)
    static func timestamp(_ date: Date) -> String {
        formatter().string(from: date)
    }

    static func folderName(at date: Date, reason: Reason) -> String {
        "\(timestamp(date))-\(reason.rawValue)"
    }

    /// `20261002T153012.123Z-upgrade` → 시각·사유
    static func parse(_ name: String) -> (at: Date, reason: Reason)? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        guard let at = formatter().date(from: String(name[..<dash])),
              let reason = Reason(rawValue: String(name[name.index(after: dash)...])) else { return nil }
        return (at, reason)
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 0700 폴더·0600 파일(umask와 상관없이).
enum PrivateFile {
    static func makeDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        try restrict(url)
    }

    static func restrict(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func size(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
