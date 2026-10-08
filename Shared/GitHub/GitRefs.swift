import Foundation

/// 작업 트리의 브랜치 목록. `.git`의 refs·packed-refs만 읽는다(git 명령을 부르지 않는다).
public struct GitRefs: Equatable, Sendable {
    public var local: [String] = []
    /// `origin`에 있는 브랜치(마지막으로 받아 온 기준)
    public var remote: Set<String> = []
    /// `origin`의 기본 브랜치. 모르면 nil
    public var defaultBranch: String?

    /// 로컬 브랜치 중 원격에도 있는 것, 이름순
    public var pushed: [String] { local.filter(remote.contains).sorted() }

    public static func read(directory: String, fileManager: FileManager = .default) -> GitRefs? {
        let probe = (directory as NSString).appendingPathComponent(".waypoint-probe")
        guard directory.hasPrefix("/"), let checkout = GitInfo.checkoutRoot(for: probe, fileManager: fileManager),
              let common = GitInfo.commonDirectory(checkout: checkout, fileManager: fileManager) else { return nil }
        var local = Set(names(under: "refs/heads", in: common, fileManager: fileManager))
        var remote = Set(names(under: "refs/remotes/origin", in: common, fileManager: fileManager))
        let packed = (try? String(contentsOfFile: (common as NSString).appendingPathComponent("packed-refs"), encoding: .utf8)) ?? ""
        for line in packed.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") && !line.hasPrefix("^") {
            guard let name = line.split(separator: " ").last else { continue }
            if name.hasPrefix("refs/heads/") { local.insert(String(name.dropFirst("refs/heads/".count))) }
            if name.hasPrefix("refs/remotes/origin/") { remote.insert(String(name.dropFirst("refs/remotes/origin/".count))) }
        }
        remote.remove("HEAD")
        let head = try? String(contentsOfFile: (common as NSString).appendingPathComponent("refs/remotes/origin/HEAD"), encoding: .utf8)
        let prefix = "ref: refs/remotes/origin/"
        let trimmed = head?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitRefs(local: local.sorted(), remote: remote,
                       defaultBranch: trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : nil)
    }

    private static func names(under relative: String, in common: String, fileManager: FileManager) -> [String] {
        let root = (common as NSString).appendingPathComponent(relative)
        guard let walker = fileManager.enumerator(atPath: root) else { return [] }
        var found: [String] = []
        for case let path as String in walker {
            var isDir: ObjCBool = false
            let full = (root as NSString).appendingPathComponent(path)
            if fileManager.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue { found.append(path) }
        }
        return found
    }
}

/// 열기 시트가 보이는 것: 저장소, 고를 수 있는 브랜치(원격에 있는 로컬 브랜치), 기본 선택.
public struct GitHubOptions: Equatable, Sendable {
    public let repo: String
    public let branches: [String]
    /// 지금 브랜치가 원격에 있으면 그것, 없으면 nil
    public let currentBranch: String?
    public let defaultBranch: String?

    public static func read(rootPath: String, home: String = NSHomeDirectory()) throws -> GitHubOptions {
        let repo = try GitHubRepo.read(rootPath: rootPath, home: home)
        let refs = GitRefs.read(directory: repo.checkout) ?? GitRefs()
        let current = GitInfo.branch(at: repo.checkout).flatMap { refs.remote.contains($0) ? $0 : nil }
        return GitHubOptions(repo: repo.name, branches: refs.pushed, currentBranch: current, defaultBranch: refs.defaultBranch)
    }
}
