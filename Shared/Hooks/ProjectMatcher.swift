import Foundation

/// `cwd` → 프로젝트. 가장 가까운(가장 긴) 상위 `rootPath`를 고른다. 보관된 프로젝트는 뺀다(`nearest`는 넣는다).
public enum ProjectMatcher {

    /// `~`를 홈으로 펼치고 끝 `/`를 뗀 표준 경로.
    public static func normalize(_ path: String, home: String = NSHomeDirectory()) -> String {
        var expanded = path
        if expanded == "~" {
            expanded = home
        } else if expanded.hasPrefix("~/") {
            expanded = home + expanded.dropFirst(1)
        }
        let standardized = (expanded as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    /// `path`가 `root`와 같거나 그 아래인지(경로 구성 요소 단위).
    public static func isInside(_ path: String, root: String) -> Bool {
        guard !root.isEmpty else { return false }
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    public static func project(for cwd: String, in projects: [Project], home: String = NSHomeDirectory()) -> Project? {
        nearest(for: cwd, in: projects.filter { $0.archivedAt == nil }, home: home)
    }

    /// 보관된 프로젝트까지 넣어 가장 가까운 것. 보관된 폴더를 미등록 폴더와 구별할 때 쓴다.
    public static func nearest(for cwd: String, in projects: [Project], home: String = NSHomeDirectory()) -> Project? {
        guard !cwd.isEmpty else { return nil }
        let target = normalize(cwd, home: home)
        return projects
            .filter { !$0.rootPath.isEmpty }
            .map { (project: $0, root: normalize($0.rootPath, home: home)) }
            .filter { isInside(target, root: $0.root) }
            .max { $0.root.count < $1.root.count }?
            .project
    }

    /// 프로젝트 기준 상대 경로. 프로젝트 밖이면 받은 그대로.
    public static func relativePath(_ path: String, in project: Project, home: String = NSHomeDirectory()) -> String {
        let root = normalize(project.rootPath, home: home)
        let target = normalize(path, home: home)
        guard target != root, isInside(target, root: root) else { return path }
        return String(target.dropFirst(root.count + (root == "/" ? 0 : 1)))
    }
}

/// 작업 폴더의 git 브랜치. `.git/HEAD`만 읽는다(git 명령을 부르지 않는다).
public enum GitInfo {
    /// 파일이 든 git 작업 트리의 최상위 폴더(절대 경로). 파일의 폴더부터 위로 올라가며 `.git`(폴더든 파일이든)이 있는
    /// 첫 폴더를 고른다. worktree·하위 모듈은 `.git`이 파일이라 그 폴더가 따로 잡힌다. 없으면(git 밖) nil.
    /// 지워진 파일도 위 폴더로 찾는다. git 명령을 부르지 않는다.
    public static func checkoutRoot(for path: String, fileManager: FileManager = .default) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var dir = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent()
        for _ in 0..<64 {
            if fileManager.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                let found = dir.path
                return found.count > 1 && found.hasSuffix("/") ? String(found.dropLast()) : found
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
        return nil
    }

    /// 작업 트리 최상위의 공용 git 폴더(config·refs가 있는 곳). worktree·하위 모듈은 `gitdir:`·`commondir`를 따라간다.
    public static func commonDirectory(checkout: String, fileManager: FileManager = .default) -> String? {
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
        return common
    }

    /// `cwd`에서 위로 올라가며 `.git`을 찾는다. `.git`이 파일(worktree)이면 `gitdir:`을 따라간다.
    public static func branch(at cwd: String, fileManager: FileManager = .default) -> String? {
        guard !cwd.isEmpty else { return nil }
        var dir = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL
        for _ in 0..<32 {
            let git = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: git.path, isDirectory: &isDir) {
                let gitDir: URL
                if isDir.boolValue {
                    gitDir = git
                } else {
                    guard let text = try? String(contentsOf: git, encoding: .utf8),
                          let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
                    else { return nil }
                    let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    gitDir = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : dir.appendingPathComponent(raw)
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
                else { return nil }
                let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
                let refPrefix = "ref: refs/heads/"
                return trimmed.hasPrefix(refPrefix) ? String(trimmed.dropFirst(refPrefix.count)) : nil
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
        return nil
    }
}
