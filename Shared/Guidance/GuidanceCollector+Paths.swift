import Foundation

extension GuidanceCollector {

    /// 등록 프로젝트 폴더 하나를 푼 것.
    public struct Root: Hashable, Sendable {
        public var key: String
        /// 심볼릭 링크를 푼 폴더
        public var path: String
        /// 폴더가 속한 git 저장소 뿌리(작업 트리면 원래 저장소). 없으면 nil.
        public var gitRoot: String?
        /// 기억 폴더 이름과 맞춰 볼 경로: 등록한 그대로·푼 경로·저장소 뿌리
        public var memoryPaths: [String]
    }

    /// 프로젝트 폴더 바로 아래에서 찾는 것: 상대 경로·종류·도구.
    static let projectFiles: [(String, GuidanceKind, GuidanceTool)] = [
        ("CLAUDE.md", .project, .claude),
        (".claude/CLAUDE.md", .project, .claude),
        ("CLAUDE.local.md", .local, .claude),
        ("AGENTS.override.md", .project, .codex),
        ("AGENTS.md", .project, .codex),
    ]

    /// 위 폴더에서 찾는 것과 Codex만 읽는 파일인지.
    static let ancestorFiles: [(String, Bool)] = [
        ("CLAUDE.md", false),
        ("CLAUDE.local.md", false),
        (".claude/CLAUDE.md", false),
        ("AGENTS.md", false),
        ("AGENTS.override.md", true),
    ]

    static let codexNames: Set<String> = ["AGENTS.md", "AGENTS.override.md"]

    func resolve(_ projects: [GuidanceProject]) -> [Root] {
        projects.compactMap { project in
            guard !project.rootPath.isEmpty else { return nil }
            let expanded = URL(fileURLWithPath: expandTilde(project.rootPath)).standardizedFileURL.path
            let path = fileSystem.resolve(expanded)
            let git = gitRoot(of: path)
            var paths = [expanded]
            for extra in [path, git].compactMap({ $0 }) where !paths.contains(extra) { paths.append(extra) }
            return Root(key: project.key, path: path, gitRoot: git, memoryPaths: paths)
        }
    }

    /// `~`·`~/…`를 이 수집의 홈으로.
    func expandTilde(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// `path`에서 위로 올라가며 `.git`을 찾는다. `.git`이 파일(작업 트리)이면 `gitdir:`이 가리키는 원래 저장소의 뿌리.
    func gitRoot(of path: String) -> String? {
        var dir = path
        while true {
            let marker = dir == "/" ? "/.git" : dir + "/.git"
            if let info = fileSystem.info(marker) {
                if info.isDirectory { return dir }
                if let data = fileSystem.read(marker, maxBytes: 4096),
                   let line = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline).first,
                   line.hasPrefix("gitdir:") {
                    var target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    if !target.hasPrefix("/") { target = dir + "/" + target }
                    target = URL(fileURLWithPath: target).standardizedFileURL.path
                    if let range = target.range(of: "/.git/worktrees/") {
                        return String(target[..<range.lowerBound])
                    }
                }
                return dir
            }
            guard dir != "/" else { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    /// 프로젝트 폴더 위의 폴더들(가까운 것부터). 홈 아래면 홈까지(홈 포함), 아니면 `/` 바로 아래까지.
    static func ancestors(of path: String, home: String) -> [String] {
        let underHome = !home.isEmpty && home != "/" && path.hasPrefix(home + "/")
        var result: [String] = []
        var dir = (path as NSString).deletingLastPathComponent
        while dir != "/" && !dir.isEmpty {
            result.append(dir)
            if underHome && dir == home { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return result
    }

    /// 폴더 아래 `.md`(하위 폴더 포함, 깊이 5까지), 이름순.
    func markdownFiles(under dir: String, depth: Int = 5) -> [String] {
        guard depth > 0, let names = fileSystem.list(dir) else { return [] }
        var result: [String] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let path = dir + "/" + name
            guard let info = fileSystem.info(path) else { continue }
            if info.isDirectory {
                result += markdownFiles(under: path, depth: depth - 1)
            } else if name.lowercased().hasSuffix(".md") {
                result.append(path)
            }
        }
        return result
    }

    /// 경로별로 출처를 모은다. 같은 파일이 여러 프로젝트에 걸리면 처음 자리(scope)를 두고 `appliesTo`만 합친다.
    struct Builder {
        let fs: any GuidanceFileSystem
        var sources: [String: GuidanceSource] = [:]

        mutating func add(
            _ path: String, kind: GuidanceKind, tool: GuidanceTool, scope: GuidanceScope,
            appliesTo: [String] = [], memoryFolder: String? = nil
        ) {
            guard let info = fs.info(path), !info.isDirectory else { return }
            let resolved = fs.resolve(path)
            if var existing = sources[resolved] {
                existing.appliesTo = Array(Set(existing.appliesTo + appliesTo)).sorted()
                sources[resolved] = existing
                return
            }
            let count = fs.read(path, maxBytes: GuidanceCollector.countLimit).map { GuidanceCount.entries(in: $0, kind: kind) }
            sources[resolved] = GuidanceSource(
                kind: kind, tool: tool, path: resolved, scope: scope, appliesTo: appliesTo.sorted(),
                memoryFolder: memoryFolder, size: info.size, modifiedAt: info.modifiedAt, entryCount: count
            )
        }

        mutating func insert(_ source: GuidanceSource) {
            if sources[source.path] == nil { sources[source.path] = source }
        }
    }
}

/// 항목 수 추정.
public enum GuidanceCount {
    public static func entries(in data: Data, kind: GuidanceKind) -> Int {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch kind {
        case .memoryIndex:
            return lines.filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }.count
        case .commandRules:
            return lines.filter { !$0.hasPrefix("#") }.count
        default:
            return lines.count
        }
    }
}
