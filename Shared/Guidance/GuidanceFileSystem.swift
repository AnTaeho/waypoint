import Foundation

/// 파일 하나의 정보.
public struct GuidanceFileInfo: Equatable, Sendable {
    public var isDirectory: Bool
    public var size: Int64
    public var modifiedAt: Date?

    public init(isDirectory: Bool, size: Int64 = 0, modifiedAt: Date? = nil) {
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

/// 출처 수집이 쓰는 파일 시스템. 읽기 동작만 있다(쓰기 메서드를 두지 않는다).
/// 테스트는 가짜로 바꾼다.
public protocol GuidanceFileSystem: Sendable {
    /// 없으면 nil. 심볼릭 링크는 따라간다.
    func info(_ path: String) -> GuidanceFileInfo?
    /// 폴더 안 이름들. 폴더가 아니거나 읽지 못하면 nil.
    func list(_ path: String) -> [String]?
    /// 앞에서 `maxBytes`까지. 없거나 읽지 못하면 nil.
    func read(_ path: String, maxBytes: Int) -> Data?
    /// 심볼릭 링크를 푼 절대 경로(없는 경로면 정리만 한 것).
    func resolve(_ path: String) -> String
}

/// 실제 디스크.
public struct DiskGuidanceFileSystem: GuidanceFileSystem {
    public init() {}

    public func info(_ path: String) -> GuidanceFileInfo? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        else { return nil }
        return GuidanceFileInfo(
            isDirectory: values.isDirectory ?? false,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
        )
    }

    public func list(_ path: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }

    public func read(_ path: String, maxBytes: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes) ?? Data()
    }

    /// `realpath`(FSEvents가 알려 주는 경로와 같게 `/private/tmp`처럼 푼다). 없는 경로는 정리만.
    public func resolve(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
