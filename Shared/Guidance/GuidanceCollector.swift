import Foundation

/// 지침·기억 출처를 모두 찾는다. 읽기만 하고 결과를 저장하지 않는다(순수: 입력 = 경로·등록 프로젝트·파일 시스템).
public struct GuidanceCollector: Sendable {
    public var home: String
    /// `~/.claude`(`CLAUDE_CONFIG_DIR`가 있으면 그 경로)
    public var claudeHome: String
    /// `~/.codex`(`CODEX_HOME`이 있으면 그 경로)
    public var codexHome: String
    /// 관리 정책 CLAUDE.md(macOS). nil이면 보지 않는다.
    public var managedClaudeFile: String?
    public var fileSystem: any GuidanceFileSystem
    /// Codex 기억 DB 행 수. 읽지 못하면 nil.
    public var codexMemoryCount: @Sendable (String) -> Int?

    /// 줄 수를 셀 때 읽는 앞부분 한도
    public static let countLimit = 1 << 20

    public init(
        home: String, claudeHome: String? = nil, codexHome: String? = nil,
        managedClaudeFile: String? = nil,
        fileSystem: any GuidanceFileSystem = DiskGuidanceFileSystem(),
        codexMemoryCount: @escaping @Sendable (String) -> Int? = { CodexMemoryStore.read(path: $0, limit: 0).count }
    ) {
        self.home = home
        self.claudeHome = claudeHome ?? home + "/.claude"
        self.codexHome = codexHome ?? home + "/.codex"
        self.managedClaudeFile = managedClaudeFile
        self.fileSystem = fileSystem
        self.codexMemoryCount = codexMemoryCount
    }

    /// 이 Mac의 기본값. 빈 환경 변수는 없는 것으로 본다.
    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> GuidanceCollector {
        func value(_ key: String) -> String? {
            guard let raw = environment[key], !raw.isEmpty else { return nil }
            return (raw as NSString).expandingTildeInPath
        }
        return GuidanceCollector(
            home: home,
            claudeHome: value("CLAUDE_CONFIG_DIR"),
            codexHome: value("CODEX_HOME"),
            managedClaudeFile: "/Library/Application Support/ClaudeCode/CLAUDE.md"
        )
    }

    public var claudeProjectsDirectory: String { claudeHome + "/projects" }

    // MARK: - 수집

    public func collect(projects: [GuidanceProject]) -> GuidanceSnapshot {
        var builder = Builder(fs: fileSystem)
        let resolvedHome = fileSystem.resolve(home)
        let roots = resolve(projects)

        collectGlobal(into: &builder)
        for root in roots {
            for (rel, kind, tool) in Self.projectFiles {
                builder.add(root.path + "/" + rel, kind: kind, tool: tool, scope: .project(root.key), appliesTo: [root.key])
            }
            for rule in markdownFiles(under: root.path + "/.claude/rules") {
                builder.add(rule, kind: .rule, tool: .claude, scope: .project(root.key), appliesTo: [root.key])
            }
        }

        var ancestors: [String] = []
        var ancestorKeys: [String: Set<String>] = [:]
        for root in roots {
            for dir in Self.ancestors(of: root.path, home: resolvedHome) {
                if !ancestors.contains(dir) { ancestors.append(dir) }
                ancestorKeys[dir, default: []].insert(root.key)
                let inRepo = root.gitRoot.map { dir == $0 || dir.hasPrefix($0 + "/") } ?? false
                for (rel, codexOnly) in Self.ancestorFiles {
                    if codexOnly && !inRepo { continue }
                    // 홈의 `.claude/CLAUDE.md`는 전역 지침이다(위에서 이미 넣었다).
                    if dir == resolvedHome && rel.hasPrefix(".claude/") { continue }
                    // 저장소 안의 AGENTS.md는 Codex가 읽는다. 저장소 밖이면 Claude만(CLAUDE.md가 없을 때) 읽는다.
                    let tool: GuidanceTool = Self.codexNames.contains(rel) && inRepo ? .codex : .claude
                    builder.add(dir + "/" + rel, kind: .ancestor, tool: tool, scope: .ancestor(dir), appliesTo: [root.key])
                }
            }
        }

        let folders = collectMemory(into: &builder, roots: roots, ancestors: ancestors, ancestorKeys: ancestorKeys)
        return GuidanceSnapshot(
            sources: builder.sources.values.sorted { $0.path < $1.path },
            memoryFolders: folders,
            ancestors: ancestors
        )
    }

    // MARK: - 전역

    private func collectGlobal(into builder: inout Builder) {
        if let managedClaudeFile {
            builder.add(managedClaudeFile, kind: .global, tool: .claude, scope: .global)
        }
        builder.add(claudeHome + "/CLAUDE.md", kind: .global, tool: .claude, scope: .global)
        for rule in markdownFiles(under: claudeHome + "/rules") {
            builder.add(rule, kind: .rule, tool: .claude, scope: .global)
        }
        // Codex는 이 자리에서 비지 않은 첫 파일 하나만 읽는다(override 먼저). 둘 다 있으면 둘 다 보인다.
        builder.add(codexHome + "/AGENTS.override.md", kind: .global, tool: .codex, scope: .global)
        builder.add(codexHome + "/AGENTS.md", kind: .global, tool: .codex, scope: .global)
        let rulesDir = codexHome + "/rules"
        for name in (fileSystem.list(rulesDir) ?? []).sorted() where name.hasSuffix(".rules") {
            builder.add(rulesDir + "/" + name, kind: .commandRules, tool: .codex, scope: .global)
        }
        let db = codexHome + "/" + CodexMemoryStore.fileName
        if let info = fileSystem.info(db), !info.isDirectory {
            builder.insert(GuidanceSource(
                kind: .codexMemory, tool: .codex, path: fileSystem.resolve(db), scope: .global,
                size: info.size, modifiedAt: info.modifiedAt, entryCount: codexMemoryCount(db)
            ))
        }
    }

    // MARK: - 자동 기억

    private func collectMemory(
        into builder: inout Builder, roots: [Root], ancestors: [String], ancestorKeys: [String: Set<String>]
    ) -> [MemoryFolder] {
        let base = claudeProjectsDirectory
        var folders: [MemoryFolder] = []
        for name in (fileSystem.list(base) ?? []).sorted() {
            let memoryDir = base + "/" + name + "/memory"
            guard fileSystem.info(memoryDir)?.isDirectory == true else { continue }
            let files = (fileSystem.list(memoryDir) ?? []).sorted()
                .filter { $0.lowercased().hasSuffix(".md") && !$0.hasPrefix(".") }
                .filter { fileSystem.info(memoryDir + "/" + $0)?.isDirectory == false }
            // 빈 기억 폴더는 보이지 않는다.
            guard !files.isEmpty else { continue }

            let match = match(name, roots: roots, ancestors: ancestors)
            let scope: GuidanceScope
            let applies: [String]
            switch match {
            case .projects(let keys):
                scope = .project(keys[0])
                applies = keys
            case .ancestor(let dir):
                scope = .ancestor(dir)
                applies = (ancestorKeys[dir] ?? []).sorted()
            case .other:
                scope = .otherFolder(name)
                applies = []
            }
            for file in files {
                builder.add(memoryDir + "/" + file, kind: file == "MEMORY.md" ? .memoryIndex : .memory, tool: .claude,
                            scope: scope, appliesTo: applies, memoryFolder: name)
            }
            folders.append(MemoryFolder(name: name, path: fileSystem.resolve(memoryDir), match: match, fileCount: files.count))
        }
        return folders
    }

    /// 기억 폴더 이름을 등록 프로젝트(폴더·git 저장소 뿌리) → 상위 폴더 순으로 맞춘다.
    public func match(_ name: String, roots: [Root], ancestors: [String]) -> MemoryFolder.Match {
        let keys = roots.filter { root in root.memoryPaths.contains { MemoryFolderName.matches(name, path: $0) } }
            .map(\.key)
        let unique = Array(Set(keys)).sorted()
        if !unique.isEmpty { return .projects(unique) }
        if let dir = ancestors.first(where: { MemoryFolderName.matches(name, path: $0) }) { return .ancestor(dir) }
        let located = MemoryFolderName.locate(name, fileSystem: fileSystem)
        return .other(path: located.path, onDisk: located.onDisk)
    }
}
