import Foundation

/// 원격(SSH)·개발 컨테이너에서 온 훅의 git 작업 트리(TRK-53, SPEC 「원격·컨테이너 수집」).
/// 원격 모드의 훅 스크립트가 payload에 `waypoint_remote: {origin, root, branch?, host?}`로 붙인다.
public struct RemoteCheckout: Equatable, Sendable {
    /// `remote.origin.url` 원문
    public let origin: String
    /// 원격 쪽 작업 트리 최상위(절대 경로)
    public let root: String
    public let branch: String?
    public let host: String?

    public init(origin: String, root: String, branch: String? = nil, host: String? = nil) {
        self.origin = origin
        self.root = root
        self.branch = branch
        self.host = host
    }

    /// payload 값. origin·root(절대 경로)가 없으면 nil.
    public init?(_ raw: Any?) {
        guard let object = raw as? [String: Any],
              let origin = object["origin"] as? String, !origin.isEmpty,
              let root = object["root"] as? String, root.hasPrefix("/")
        else { return nil }
        func text(_ key: String) -> String? {
            (object[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        self.init(origin: origin, root: ProjectMatcher.normalize(root), branch: text("branch"), host: text("host"))
    }

    /// `file.changed`의 `checkout`(같은 작업 트리 판정 열쇠, TRK-17). 원격 작업 트리는 Mac의 체크아웃과 다른 값이어야
    /// 같은 파일을 로컬과 원격에서 고쳐도 「같은 작업 트리」로 보지 않는다.
    public var checkoutID: String {
        host.map { "\($0):\(root)" } ?? root
    }
}

/// git 원격 주소 정규화. 같은 저장소를 가리키는 여러 꼴을 한 문자열로 모은다.
/// `git@github.com:a/b.git` = `ssh://git@github.com/a/b` = `https://github.com/a/b/` → `github.com/a/b`.
/// 사용자 정보(`user@`, `user:token@`)·포트·끝 `.git`·끝 `/`를 떼고 소문자로 바꾼다. 로컬 경로(`/srv/b.git`, `file://`)는 경로만.
public enum GitRemoteURL {
    public static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var host = ""
        var path: String
        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
            let slash = text.firstIndex(of: "/") ?? text.endIndex
            host = String(text[..<slash])
            path = String(text[slash...])
        } else if !text.hasPrefix("/"), let colon = text.firstIndex(of: ":"),
                  !text[..<colon].contains("/") {
            // scp 꼴 `user@host:path`
            host = String(text[..<colon])
            path = String(text[text.index(after: colon)...])
        } else {
            path = text
        }
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]") { host = String(host[..<colon]) }
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        while path.hasSuffix("/") { path.removeLast() }
        if !host.isEmpty { while path.hasPrefix("/") { path.removeFirst() } }
        guard !path.isEmpty else { return nil }
        return (host.isEmpty ? path : host + "/" + path).lowercased()
    }
}

/// 등록 프로젝트의 로컬 git 정보: 작업 트리 최상위와 정규화한 `origin` 주소.
public struct LocalOrigin: Equatable, Sendable {
    public let checkout: String
    public let url: String

    public init(checkout: String, url: String) {
        self.checkout = checkout
        self.url = url
    }

    /// `rootPath`가 든 작업 트리의 `.git/config`에서 `[remote "origin"] url`을 읽는다. git 명령을 부르지 않는다.
    /// worktree·하위 모듈(`.git`이 파일)은 `gitdir:`·`commondir`를 따라간다. origin이 없거나 git 밖이면 nil.
    public static func read(rootPath: String, fileManager: FileManager = .default) -> LocalOrigin? {
        guard rootPath.hasPrefix("/"),
              let checkout = GitInfo.checkoutRoot(for: (rootPath as NSString).appendingPathComponent(".waypoint-probe"),
                                                  fileManager: fileManager)
        else { return nil }
        let dotGit = (checkout as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        var gitDir = dotGit
        if !isDir.boolValue {
            guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8),
                  let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
            else { return nil }
            let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = raw.hasPrefix("/") ? raw : (checkout as NSString).appendingPathComponent(raw)
        }
        var common = gitDir
        if let text = try? String(contentsOfFile: (gitDir as NSString).appendingPathComponent("commondir"), encoding: .utf8) {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty { common = raw.hasPrefix("/") ? raw : (gitDir as NSString).appendingPathComponent(raw) }
        }
        guard let config = try? String(contentsOfFile: (common as NSString).appendingPathComponent("config"), encoding: .utf8),
              let origin = originURL(config: config), let url = GitRemoteURL.normalize(origin)
        else { return nil }
        return LocalOrigin(checkout: checkout, url: url)
    }

    /// git config 글에서 `[remote "origin"]`의 `url`. 없으면 nil.
    public static func originURL(config: String) -> String? {
        var inOrigin = false
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line == "[remote \"origin\"]"
                continue
            }
            guard inOrigin, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "url" else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

/// 프로젝트 폴더 → 로컬 origin. 원격 훅이 올 때만 읽고, 5분 동안 기억한다(원격 주소는 거의 바뀌지 않는다).
/// 앱의 처리기·MCP가 메인 액터에서 함께 쓴다.
public final class LocalOriginCache: @unchecked Sendable {
    public static let shared = LocalOriginCache()
    public static let lifetime: TimeInterval = 5 * 60

    private let lock = NSLock()
    private var entries: [String: (value: LocalOrigin?, at: Date)] = [:]
    private let reader: (String) -> LocalOrigin?
    private let now: () -> Date

    public init(reader: @escaping (String) -> LocalOrigin? = { LocalOrigin.read(rootPath: $0) },
                now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.now = now
    }

    public func origin(for rootPath: String) -> LocalOrigin? {
        let date = now()
        lock.lock()
        if let entry = entries[rootPath], date.timeIntervalSince(entry.at) < Self.lifetime {
            lock.unlock()
            return entry.value
        }
        lock.unlock()
        let value = reader(rootPath)
        lock.lock()
        entries[rootPath] = (value, date)
        lock.unlock()
        return value
    }
}

/// 원격 작업 트리 ↔ 등록 프로젝트의 로컬 작업 트리(TRK-53).
public enum RemoteMatcher {

    /// 같은 원격 주소를 가진 보관 안 된 등록 프로젝트의 로컬 작업 트리. 작업 트리가 하나로 정해질 때만(둘 이상이면 nil).
    /// 한 작업 트리 안의 여러 프로젝트(모노레포 하위 폴더)는 같은 작업 트리라 하나로 본다. 경로를 옮긴 뒤 가까운 프로젝트가 고른다.
    public static func localCheckout(origin: String, in projects: [Project], home: String = NSHomeDirectory(),
                                     localOrigin: (String) -> LocalOrigin?) -> String? {
        guard let url = GitRemoteURL.normalize(origin) else { return nil }
        let checkouts = Set(projects
            .filter { $0.archivedAt == nil && !$0.rootPath.isEmpty }
            .compactMap { localOrigin(ProjectMatcher.normalize($0.rootPath, home: home)) }
            .filter { $0.url == url }
            .map(\.checkout))
        return checkouts.count == 1 ? checkouts.first : nil
    }

    /// 원격 훅을 로컬 작업 트리에 이을지. 훅 `cwd`가 어떤 등록 폴더(보관 포함)와도 맞지 않고, 원격 작업 트리 경로가
    /// 이 Mac에 없을 때만(로컬의 다른 클론·worktree는 지금처럼 미등록 폴더로 둔다). 이을 로컬 작업 트리, 아니면 nil.
    public static func link(_ remote: RemoteCheckout, cwd: String, in projects: [Project], home: String = NSHomeDirectory(),
                            localOrigin: (String) -> LocalOrigin?, pathExists: (String) -> Bool) -> String? {
        guard !cwd.isEmpty, ProjectMatcher.nearest(for: cwd, in: projects, home: home) == nil,
              !pathExists(remote.root)
        else { return nil }
        return localCheckout(origin: remote.origin, in: projects, home: home, localOrigin: localOrigin)
    }

    /// 원격 작업 트리 아래 경로를 로컬 작업 트리 아래로 옮긴다. 밖이면 그대로.
    public static func map(_ path: String, from remoteRoot: String, to localRoot: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let target = (path as NSString).standardizingPath
        if target == remoteRoot { return localRoot }
        guard ProjectMatcher.isInside(target, root: remoteRoot) else { return path }
        let rest = target.dropFirst(remoteRoot.count + (remoteRoot == "/" ? 0 : 1))
        return (localRoot as NSString).appendingPathComponent(String(rest))
    }
}
