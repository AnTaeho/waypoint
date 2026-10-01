import Foundation

extension GuidanceDocument {

    /// 원문 바이트를 항목으로 나눈다. UTF-8이 아니면 편집할 수 없는 문서 전체 한 항목.
    public static func parse(data: Data, format: GuidanceDocumentFormat) -> GuidanceDocument {
        // 깨진 바이트는 대체 문자가 되어 바이트가 달라진다. BOM은 글자로 남는다.
        let text = String(decoding: data, as: UTF8.self)
        if Array(text.utf8) == Array(data) { return parse(text, format: format) }
        let lines = GuidanceLines(text)
        var document = whole(lines, format: format, reason: "UTF-8로 읽을 수 없음")
        document.isEditable = false
        return document
    }

    /// 원문을 항목으로 나눈다. 나누기 애매하면 문서 전체를 한 항목으로 두고 `ambiguity`에 이유를 적는다.
    public static func parse(_ source: String, format: GuidanceDocumentFormat) -> GuidanceDocument {
        let lines = GuidanceLines(source)
        guard lines.count > 0 else {
            return GuidanceDocument(format: format, source: source, segments: [], ambiguity: nil, lineTable: [])
        }
        var reasons: [String] = []
        var items: [GuidanceItem]
        var allowedTrivia: (Int) -> Bool
        switch format {
        case .markdown, .memoryIndex:
            var splitter = GuidanceMarkdownSplitter(lines)
            items = splitter.split()
            reasons = splitter.reasons
            if format == .memoryIndex { items = items.map(indexEntry) }
            allowedTrivia = {
                lines.isBlank($0) || MarkdownParser.isRule(lines.trimmed($0))
                    || GuidanceMarkdownSplitter.isLineComment(lines.trimmed($0))
            }
        case .memory:
            items = [memoryItem(lines)]
            allowedTrivia = { _ in false }
        case .commandRules:
            var splitter = GuidanceRulesSplitter(lines)
            items = splitter.split()
            reasons = splitter.reasons
            allowedTrivia = { lines.isBlank($0) || GuidanceRulesSplitter.isComment(lines.trimmed($0)) }
        }

        for index in items.indices { items[index] = numbered(items[index], id: [index]) }
        let (segments, problem) = segments(items, lines: lines, allowedTrivia: allowedTrivia)
        if let problem { reasons.append(problem) }
        if reasons.isEmpty, Array(segments.map(\.raw).joined().utf8) != lines.bytes {
            reasons.append("다시 합친 결과가 원문과 다름")
        }
        if !reasons.isEmpty { return whole(lines, format: format, reason: reasons.joined(separator: ", ")) }
        return GuidanceDocument(format: format, source: source, segments: segments, ambiguity: nil, lineTable: lines.lines)
    }

    // MARK: - 조각

    private static func numbered(_ item: GuidanceItem, id: [Int]) -> GuidanceItem {
        var item = item
        item.id = id
        item.children = item.children.enumerated().map { numbered($1, id: id + [$0]) }
        return item
    }

    /// 항목 사이 줄을 trivia로 채운다. 항목이 겹치거나 의미 있는 줄이 빠지면 이유를 돌려준다.
    private static func segments(
        _ items: [GuidanceItem], lines: GuidanceLines, allowedTrivia: (Int) -> Bool
    ) -> ([GuidanceSegment], String?) {
        var segments: [GuidanceSegment] = []
        var line = 0
        var problem: String?
        func trivia(upTo end: Int) {
            guard line < end else { return }
            if (line..<end).contains(where: { !allowedTrivia($0) }) { problem = problem ?? "항목에 들지 않은 줄이 있음" }
            segments.append(.trivia(lines.string(lines.lines[line].start..<lines.lines[end - 1].end)))
        }
        for item in items {
            guard item.lines.lowerBound >= line else { return (segments, "항목이 겹침") }
            trivia(upTo: item.lines.lowerBound)
            segments.append(.item(item))
            line = item.lines.upperBound
        }
        trivia(upTo: lines.count)
        return (segments, problem)
    }

    private static func whole(_ lines: GuidanceLines, format: GuidanceDocumentFormat, reason: String) -> GuidanceDocument {
        guard lines.count > 0 else {
            return GuidanceDocument(format: format, source: lines.string(0..<lines.bytes.count), segments: [],
                                    ambiguity: reason, lineTable: [])
        }
        var item = lines.item(kind: .document, first: 0, last: lines.count - 1, section: [], display: "")
        item.id = [0]
        return GuidanceDocument(format: format, source: lines.string(0..<lines.bytes.count),
                                segments: [.item(item)], ambiguity: reason, lineTable: lines.lines)
    }

    // MARK: - 기억

    /// 기억 파일: frontmatter + 본문 전체가 한 항목
    private static func memoryItem(_ lines: GuidanceLines) -> GuidanceItem {
        var fields = GuidanceMemoryFields()
        var bodyStart = 0
        if let close = GuidanceMarkdownSplitter.frontmatterClose(lines) {
            fields = memoryFields(Array(lines.contents[1..<close]))
            bodyStart = close + 1
        }
        let firstLine = (bodyStart..<lines.count).first { !lines.isBlank($0) }.map { lines.trimmed($0) }
        let display = fields.description ?? fields.name ?? firstLine ?? ""
        var item = lines.item(kind: .memory, first: 0, last: lines.count - 1, section: [], display: display)
        item.memory = fields
        return item
    }

    /// `name`·`description`는 맨 위 키, `type`은 맨 위 또는 `metadata:` 아래.
    static func memoryFields(_ header: [String]) -> GuidanceMemoryFields {
        var fields = GuidanceMemoryFields()
        var nestedType: String?
        var parent: String?
        for line in header {
            let indented = line.first == " " || line.first == "\t"
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
            var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q {
                value = String(value.dropFirst().dropLast())
            }
            if !indented {
                parent = key
                switch key {
                case "name": fields.name = value.isEmpty ? nil : value
                case "description": fields.description = value.isEmpty ? nil : value
                case "type": fields.type = value.isEmpty ? nil : value
                default: break
                }
            } else if key == "type", parent == "metadata", !value.isEmpty {
                nestedType = value
            }
        }
        if fields.type == nil { fields.type = nestedType }
        return fields
    }

    /// 색인 줄: 맨 위 목록 항목이 `[제목](파일)`로 시작하면
    private static func indexEntry(_ item: GuidanceItem) -> GuidanceItem {
        guard item.kind == .bullet || item.kind == .numbered,
              let match = item.display.firstMatch(of: #/^\[([^\]]*)\]\(([^)\s]+)\)/#) else { return item }
        var item = item
        item.kind = .indexEntry
        item.link = String(match.2)
        return item
    }
}
