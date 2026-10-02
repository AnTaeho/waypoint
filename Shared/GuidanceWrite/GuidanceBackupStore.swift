import CryptoKit
import Foundation

/// 프로젝트 밖 지침 파일(전역·상위 폴더·기억·Codex 규칙)을 쓰기 직전에 남기는 사본. 이 Mac에만 둔다
/// (SwiftData·CloudKit에 넣지 않는다).
///
/// 자리: `<저장 폴더>/guidance-backups/<원본 경로 SHA-256 앞 32자>/<UTC 시각>-<까닭>.<원래 확장자>`,
/// 같은 폴더의 `source-path`에 원본 절대 경로. 폴더 0700, 파일 0600. 원본 하나에 최근 `limit`개만 남긴다.
public struct GuidanceBackupStore: Sendable {

    /// 사본을 남긴 까닭(무엇을 하기 직전이었나).
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        /// 항목 고치기
        case edit
        /// 항목·파일 지우기
        case delete
        /// 백업에서 되돌리기
        case restore
        /// 지움 알림의 되돌리기
        case undo
    }

    /// 사본 하나.
    public struct Backup: Identifiable, Hashable, Sendable {
        public var id: String { url.path }
        public var url: URL
        /// 원본 절대 경로
        public var path: String
        public var at: Date
        public var reason: Reason
    }

    public static let folderName = "guidance-backups"
    /// 원본 하나에 남기는 사본 수
    public static let limit = 50
    static let metaName = "source-path"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 앱 저장 폴더(`WAYPOINT_SUPPORT_DIR`를 따른다) 아래.
    public static func appDefault() throws -> GuidanceBackupStore {
        GuidanceBackupStore(root: try WaypointStore.supportDirectory().appendingPathComponent(folderName, isDirectory: true))
    }

    /// 원본 경로의 폴더 이름.
    public static func key(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    // MARK: - 쓰기

    /// `data`를 `path`의 사본으로 남기고 오래된 것을 정리한다.
    @discardableResult
    public func save(_ data: Data, of path: String, reason: Reason, at date: Date) throws -> Backup {
        let dir = folder(for: path)
        try makePrivateDirectory(root)
        try makePrivateDirectory(dir)
        let meta = dir.appendingPathComponent(Self.metaName)
        if (try? String(contentsOf: meta, encoding: .utf8)) != path {
            try writePrivate(Data(path.utf8), to: meta)
        }
        let ext = Self.fileExtension(of: path)
        // 같은 밀리초(또는 더 늦은 시각)의 사본이 이미 있으면 그 뒤로 1 ms씩 밀어 이름 순서 = 남긴 순서를 지킨다.
        var millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        if let last = files(in: dir).last.flatMap({ Self.parse($0) }) {
            millis = max(millis, Int64((last.at.timeIntervalSince1970 * 1000).rounded()) + 1)
        }
        // DateFormatter는 밀리초를 반올림하므로 부동소수 오차가 있어도 같은 밀리초로 찍힌다
        let stamp = Date(timeIntervalSince1970: Double(millis) / 1000)
        let url = dir.appendingPathComponent(Self.fileName(at: stamp, reason: reason, ext: ext))
        try writePrivate(data, to: url)
        prune(dir)
        return Backup(url: url, path: path, at: Self.parse(url.lastPathComponent)?.at ?? stamp, reason: reason)
    }

    // MARK: - 읽기

    /// `path`의 사본(최신순).
    public func backups(of path: String) -> [Backup] {
        let dir = folder(for: path)
        return files(in: dir).reversed().compactMap { name in
            Self.parse(name).map { Backup(url: dir.appendingPathComponent(name), path: path, at: $0.at, reason: $0.reason) }
        }
    }

    public func content(of backup: Backup) throws -> Data {
        try Data(contentsOf: backup.url)
    }

    /// 사본이 있는 모든 원본 경로(이름순).
    public func backedUpPaths() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap { name in
            try? String(contentsOf: root.appendingPathComponent(name).appendingPathComponent(Self.metaName), encoding: .utf8)
        }.sorted()
    }

    // MARK: - 내부

    func folder(for path: String) -> URL {
        root.appendingPathComponent(Self.key(for: path), isDirectory: true)
    }

    /// 사본 파일 이름(오래된 것부터).
    private func files(in dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { Self.parse($0) != nil }.sorted()
    }

    private func prune(_ dir: URL) {
        let names = files(in: dir)
        for name in names.dropLast(Self.limit) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func makePrivateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// 0600으로 만든 뒤 내용을 쓴다(umask와 상관없이).
    private func writePrivate(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func fileExtension(of path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "md" : ext
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter
    }

    static func fileName(at date: Date, reason: Reason, ext: String) -> String {
        "\(formatter().string(from: date))-\(reason.rawValue).\(ext)"
    }

    /// `20261002T153012.123Z-edit.md` → 시각·까닭
    static func parse(_ name: String) -> (at: Date, reason: Reason)? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        let stamp = String(name[..<dash])
        let rest = name[name.index(after: dash)...]
        let reasonText = rest.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        guard let at = formatter().date(from: stamp), let reason = Reason(rawValue: reasonText) else { return nil }
        return (at, reason)
    }
}
