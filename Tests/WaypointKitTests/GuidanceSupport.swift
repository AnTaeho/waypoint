import Foundation
@testable import WaypointKit

/// 메모리 안의 가짜 파일 시스템. 부른 동작을 모두 적어 둔다(쓰기 동작은 프로토콜에 없다).
final class FakeGuidanceFileSystem: GuidanceFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var directories: Set<String> = ["/"]
    private var links: [String: String] = [:]
    private var log: [String] = []
    let modified = Date(timeIntervalSince1970: 1_790_000_000)

    @discardableResult
    func file(_ path: String, _ content: String = "x\n") -> Self {
        lock.withLock {
            files[path] = Data(content.utf8)
            addParents(of: path)
        }
        return self
    }

    @discardableResult
    func directory(_ path: String) -> Self {
        lock.withLock {
            directories.insert(path)
            addParents(of: path)
        }
        return self
    }

    /// `path`가 `target`을 가리키는 링크
    func link(_ path: String, to target: String) {
        lock.withLock {
            links[path] = target
            addParents(of: path)
        }
    }

    var calls: [String] { lock.withLock { log } }

    private func addParents(of path: String) {
        var dir = (path as NSString).deletingLastPathComponent
        while !dir.isEmpty {
            directories.insert(dir)
            if dir == "/" { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    private func real(_ path: String) -> String {
        for (link, target) in links {
            if path == link { return target }
            if path.hasPrefix(link + "/") { return target + path.dropFirst(link.count) }
        }
        return path
    }

    func info(_ path: String) -> GuidanceFileInfo? {
        lock.withLock {
            log.append("info \(path)")
            let path = real(path)
            if directories.contains(path) { return GuidanceFileInfo(isDirectory: true, modifiedAt: modified) }
            guard let data = files[path] else { return nil }
            return GuidanceFileInfo(isDirectory: false, size: Int64(data.count), modifiedAt: modified)
        }
    }

    func list(_ path: String) -> [String]? {
        lock.withLock {
            log.append("list \(path)")
            let path = real(path)
            guard directories.contains(path) else { return nil }
            let prefix = path == "/" ? "/" : path + "/"
            var names: Set<String> = []
            for child in Array(files.keys) + Array(directories) + Array(links.keys) where child.hasPrefix(prefix) && child != path {
                let rest = child.dropFirst(prefix.count)
                if let first = rest.split(separator: "/").first { names.insert(String(first)) }
            }
            return Array(names)
        }
    }

    func read(_ path: String, maxBytes: Int) -> Data? {
        lock.withLock {
            log.append("read \(path)")
            return files[real(path)].map { $0.prefix(maxBytes) }
        }
    }

    func resolve(_ path: String) -> String {
        lock.withLock { real(path) }
    }
}
