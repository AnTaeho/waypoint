import Foundation

/// 지침·기억 출처를 읽는 도구.
public enum GuidanceTool: String, Sendable, Hashable, CaseIterable {
    case claude, codex
}

/// 출처 종류.
public enum GuidanceKind: String, Sendable, Hashable, CaseIterable {
    /// `~/.claude/CLAUDE.md`, 관리 정책 CLAUDE.md, `~/.codex/AGENTS.md`(·override)
    case global
    /// 등록 프로젝트 위 폴더의 CLAUDE.md·CLAUDE.local.md·.claude/CLAUDE.md·AGENTS.md
    case ancestor
    /// 프로젝트 CLAUDE.md·.claude/CLAUDE.md·AGENTS.md·AGENTS.override.md
    case project
    /// 프로젝트 CLAUDE.local.md
    case local
    /// `.claude/rules/**/*.md`(전역·프로젝트)
    case rule
    /// 자동 기억 한 항목(`memory/*.md`)
    case memory
    /// 자동 기억 색인(`memory/MEMORY.md`)
    case memoryIndex
    /// Codex 명령 규칙(`~/.codex/rules/*.rules`)
    case commandRules
    /// Codex 내부 기억 DB(`memories_1.sqlite`)
    case codexMemory
}

/// 화면에서 출처를 묶는 자리.
public enum GuidanceScope: Hashable, Sendable {
    case global
    /// 등록 프로젝트 위 폴더(절대 경로)
    case ancestor(String)
    /// 등록 프로젝트(키)
    case project(String)
    /// 등록 프로젝트·상위 폴더와 맞지 않는 기억 폴더(이름)
    case otherFolder(String)
}

/// 출처 하나(파일 하나, 또는 Codex 기억 DB).
public struct GuidanceSource: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var kind: GuidanceKind
    public var tool: GuidanceTool
    /// 절대 경로(심볼릭 링크를 푼 것)
    public var path: String
    public var scope: GuidanceScope
    /// 이 출처가 걸리는 등록 프로젝트 키(이름순). 전역은 비운다(모든 프로젝트).
    public var appliesTo: [String]
    /// 기억 파일이면 그 기억 폴더 이름(`~/.claude/projects/<이름>`)
    public var memoryFolder: String?
    public var size: Int64
    public var modifiedAt: Date?
    /// 항목 수 추정. 색인은 목록 줄 수, 명령 규칙은 규칙 줄 수, Codex 기억은 행 수, 그 밖은 비지 않은 줄 수.
    /// 읽지 못하면 nil.
    public var entryCount: Int?

    public init(
        kind: GuidanceKind, tool: GuidanceTool, path: String, scope: GuidanceScope,
        appliesTo: [String] = [], memoryFolder: String? = nil,
        size: Int64 = 0, modifiedAt: Date? = nil, entryCount: Int? = nil
    ) {
        self.kind = kind
        self.tool = tool
        self.path = path
        self.scope = scope
        self.appliesTo = appliesTo
        self.memoryFolder = memoryFolder
        self.size = size
        self.modifiedAt = modifiedAt
        self.entryCount = entryCount
    }

    public var isMemory: Bool { kind == .memory || kind == .memoryIndex }
}

/// `~/.claude/projects/<이름>/memory` 폴더 하나와 짝지은 결과.
public struct MemoryFolder: Identifiable, Hashable, Sendable {
    public enum Match: Hashable, Sendable {
        /// 등록 프로젝트(키, 이름순). 같은 이름으로 바뀌는 프로젝트가 여럿이면 모두.
        case projects([String])
        /// 등록 프로젝트 위 폴더(절대 경로)
        case ancestor(String)
        /// 맞는 곳 없음. `path`는 이름에서 되돌린 폴더 추정, `onDisk`는 그 폴더가 실제로 있어 확인한 것인지.
        case other(path: String, onDisk: Bool)
    }

    public var id: String { name }
    public var name: String
    /// memory 폴더 절대 경로
    public var path: String
    public var match: Match
    /// `.md` 파일 수
    public var fileCount: Int

    public init(name: String, path: String, match: Match, fileCount: Int) {
        self.name = name
        self.path = path
        self.match = match
        self.fileCount = fileCount
    }
}

/// 수집 입력의 등록 프로젝트.
public struct GuidanceProject: Hashable, Sendable {
    public var key: String
    public var rootPath: String

    public init(key: String, rootPath: String) {
        self.key = key
        self.rootPath = rootPath
    }
}

/// 한 번 모은 결과. 저장하지 않는다.
public struct GuidanceSnapshot: Equatable, Sendable {
    public var sources: [GuidanceSource]
    public var memoryFolders: [MemoryFolder]
    /// 등록 프로젝트 위 폴더(가까운 것부터, 중복 없음)
    public var ancestors: [String]

    public init(sources: [GuidanceSource] = [], memoryFolders: [MemoryFolder] = [], ancestors: [String] = []) {
        self.sources = sources
        self.memoryFolders = memoryFolders
        self.ancestors = ancestors
    }

    public static let empty = GuidanceSnapshot()

    public func sources(in scope: GuidanceScope) -> [GuidanceSource] {
        sources.filter { $0.scope == scope }
    }

    /// 이 프로젝트에 걸린 출처: 전역 + 상위 폴더·프로젝트·기억 중 `appliesTo`에 키가 있는 것.
    public func applying(to key: String) -> [GuidanceSource] {
        sources.filter { $0.scope == .global || $0.appliesTo.contains(key) }
    }

    /// 짝짓지 못한 기억 폴더 이름(이름순)
    public var otherFolders: [String] {
        memoryFolders.compactMap { folder in
            if case .other = folder.match { folder.name } else { nil }
        }
    }
}
