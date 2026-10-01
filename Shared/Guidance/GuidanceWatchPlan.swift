import Foundation

/// 출처가 바뀌는 것을 알아챌 폴더와, 이벤트가 난 경로 중 다시 모을 만한 것을 고르는 규칙.
///
/// FSEvents는 폴더 아래를 모두 본다. `~/.claude`·`~/.codex`에는 대화 기록·로그가 쉬지 않고 쓰이므로
/// 이름으로 걸러서 디바운스가 끝없이 밀리지 않게 한다. 홈 폴더 자체는 감시하지 않는다.
public struct GuidanceWatchPlan: Equatable, Sendable {
    public var roots: Set<String>
    public var claudeProjectsDirectory: String

    public static let fileNames: Set<String> = [
        "CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", "AGENTS.override.md", CodexMemoryStore.fileName,
    ]
    /// 통째로 생기거나 지워지면 출처가 바뀌는 폴더 이름
    public static let folderNames: Set<String> = ["memory", "rules", ".claude"]

    public init(collector: GuidanceCollector, projects: [GuidanceProject], ancestors: [String]) {
        let home = collector.fileSystem.resolve(collector.home)
        var candidates: Set<String> = [collector.claudeHome, collector.codexHome]
        for project in collector.resolve(projects) { candidates.insert(project.path) }
        for dir in ancestors { candidates.insert(dir) }
        candidates = Set(candidates.map { collector.fileSystem.resolve($0) }.filter { $0 != home && $0 != "/" && !$0.isEmpty })
        roots = Self.outermost(candidates)
        claudeProjectsDirectory = collector.fileSystem.resolve(collector.claudeProjectsDirectory)
    }

    /// 다른 폴더 안에 든 폴더는 뺀다(FSEvents가 아래까지 본다).
    static func outermost(_ paths: Set<String>) -> Set<String> {
        Set(paths.filter { path in !paths.contains { other in other != path && path.hasPrefix(other + "/") } })
    }

    /// 이 경로의 변경이 출처 목록을 바꿀 수 있나.
    public func accepts(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        if Self.fileNames.contains(name) || Self.folderNames.contains(name) { return true }
        // `-shm`은 읽기만 해도 바뀔 수 있어(이 앱의 읽기 포함) 보지 않는다. 쓰기는 `-wal`로 드러난다.
        if name == CodexMemoryStore.fileName + "-wal" { return true }
        if name.hasSuffix(".rules") { return true }
        if parent.hasSuffix("/memory") && name.lowercased().hasSuffix(".md") { return true }
        if path.contains("/rules/") && name.lowercased().hasSuffix(".md") { return true }
        // 기억 폴더의 부모(`~/.claude/projects/<이름>`)가 생기거나 지워질 때
        if parent == claudeProjectsDirectory { return true }
        return false
    }
}
