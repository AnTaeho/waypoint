import Foundation

/// 지침 문서의 형식. 출처 종류(`GuidanceKind`)에서 정한다.
public enum GuidanceDocumentFormat: String, Sendable, Hashable, CaseIterable {
    /// CLAUDE.md·AGENTS.md·`.claude/rules/*.md` 등 Markdown 지침
    case markdown
    /// 자동 기억 한 파일(`memory/*.md`): 파일 하나가 항목 하나
    case memory
    /// 자동 기억 색인(`memory/MEMORY.md`): 색인 줄마다 항목
    case memoryIndex
    /// Codex 명령 규칙(`*.rules`): 한 규칙(보통 한 줄)이 항목 하나
    case commandRules

    /// 항목으로 나눌 수 있는 출처면 그 형식. Codex 기억 DB는 nil.
    public init?(kind: GuidanceKind) {
        switch kind {
        case .memory: self = .memory
        case .memoryIndex: self = .memoryIndex
        case .commandRules: self = .commandRules
        case .codexMemory: return nil
        case .global, .ancestor, .project, .local, .rule: self = .markdown
        }
    }
}

/// 지침 항목 종류.
public enum GuidanceItemKind: String, Sendable, Hashable, CaseIterable {
    /// `-`·`*`·`+` 목록 한 줄(이어지는 줄·하위 목록 포함)
    case bullet
    /// `1.`·`1)` 번호 목록 한 줄
    case numbered
    case paragraph
    /// 표 머리 줄 + 구분 줄
    case tableHeader
    case tableRow
    /// 울타리 코드 블록(여는 줄부터 닫는 줄까지)
    case code
    /// `#` 절 머리
    case heading
    /// `>` 인용 묶음
    case quote
    /// 맨 앞 `---` … `---`
    case frontmatter
    /// Codex 명령 규칙 하나
    case rule
    /// 기억 파일 하나(frontmatter + 본문)
    case memory
    /// `MEMORY.md`의 `- [제목](파일.md) — …` 줄
    case indexEntry
    /// 나누지 않은 문서 전체
    case document
}

/// 기억 파일 머리의 값.
public struct GuidanceMemoryFields: Hashable, Sendable {
    public var name: String?
    public var description: String?
    /// 맨 위 `type:` 또는 `metadata:` 아래 `type:`
    public var type: String?

    public init(name: String? = nil, description: String? = nil, type: String? = nil) {
        self.name = name
        self.description = description
        self.type = type
    }
}

/// 지침 항목 하나. 범위는 원문 UTF-8 바이트 위치다(항상 줄 경계).
public struct GuidanceItem: Hashable, Sendable, Identifiable {
    /// 문서 안 위치(맨 위 항목 번호, 하위 항목 번호, …)
    public var id: [Int]
    public var kind: GuidanceItemKind
    /// 첫 줄 시작부터 마지막 줄의 줄 끝 개행까지(개행 포함)
    public var range: Range<Int>
    /// `range`에서 마지막 줄 끝 개행을 뺀 것. `replace`가 바꾸는 자리.
    public var contentRange: Range<Int>
    /// 줄 번호(0부터)
    public var lines: Range<Int>
    /// 원문 그대로(마지막 줄 끝 개행 제외). 들여쓰기·목록 기호 포함.
    public var text: String
    /// 마지막 줄 끝 개행(`"\n"`, `"\r\n"`, 또는 파일 끝이면 `""`)
    public var terminator: String
    /// 소속 절 머리 경로(바깥부터). 절 머리 자신은 넣지 않는다.
    public var section: [String]
    /// 화면에 보일 글(기호·들여쓰기를 걷어 내고 줄을 이은 것)
    public var display: String
    /// 목록 기호(`-`, `*`, `+`, `1.`, `2)` …). 목록이 아니면 nil.
    public var marker: String?
    /// 하위 목록 항목. 이들의 범위는 이 항목 범위 안에 있다.
    public var children: [GuidanceItem]
    /// 기억 파일 머리(종류 `.memory`)
    public var memory: GuidanceMemoryFields?
    /// 색인 줄이 가리키는 파일(종류 `.indexEntry`)
    public var link: String?

    /// 원문 그대로(마지막 개행 포함)
    public var raw: String { text + terminator }

    /// 자신과 모든 하위 항목(앞 순서)
    public var flattened: [GuidanceItem] { [self] + children.flatMap(\.flattened) }
}

/// 다시 합치기 위한 조각: 항목이거나, 항목이 아닌 줄(빈 줄·구분선·주석).
public enum GuidanceSegment: Hashable, Sendable {
    case item(GuidanceItem)
    case trivia(String)

    public var raw: String {
        switch self {
        case .item(let item): item.raw
        case .trivia(let text): text
        }
    }
}

/// 항목으로 나눈 지침 문서. 문자열만 다룬다(파일을 쓰지 않는다).
public struct GuidanceDocument: Sendable {
    public var format: GuidanceDocumentFormat
    /// 원문
    public var source: String
    /// 원문 순서대로 맨 위 조각. 이어 붙이면 원문과 바이트까지 같다.
    public var segments: [GuidanceSegment]
    /// 나누기 애매해 문서 전체를 한 항목으로 둔 이유. 나눴으면 nil.
    public var ambiguity: String?
    /// 원문을 바이트 그대로 편집할 수 있는지(UTF-8로 읽지 못한 원문은 false)
    public var isEditable: Bool

    let lineTable: [GuidanceLine]
    let sourceBytes: [UInt8]

    init(format: GuidanceDocumentFormat, source: String, segments: [GuidanceSegment], ambiguity: String?,
         isEditable: Bool = true, lineTable: [GuidanceLine]) {
        self.format = format
        self.source = source
        self.segments = segments
        self.ambiguity = ambiguity
        self.isEditable = isEditable
        self.lineTable = lineTable
        self.sourceBytes = Array(source.utf8)
    }

    /// 맨 위 항목
    public var items: [GuidanceItem] {
        segments.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    /// 모든 항목(하위 포함, 원문 순서)
    public var allItems: [GuidanceItem] { items.flatMap(\.flattened) }

    public var isAmbiguous: Bool { ambiguity != nil }

    /// 조각을 이어 붙인 문서
    public func joined() -> String { segments.map(\.raw).joined() }

    /// `id`로 항목 찾기
    public func item(id: [Int]) -> GuidanceItem? {
        guard let first = id.first, items.indices.contains(first) else { return nil }
        var item = items[first]
        for index in id.dropFirst() {
            guard item.children.indices.contains(index) else { return nil }
            item = item.children[index]
        }
        return item
    }
}
