import Foundation

/// Markdown 블록. 인라인 문법(굵게·기울임·코드·링크)은 글자 그대로 두고 화면에서 `AttributedString`으로 푼다.
public enum MarkdownBlock: Equatable, Sendable {
    /// `#`~`######`. 화면은 1~3단계만 구분한다.
    case heading(level: Int, text: String)
    /// 이어진 줄은 공백 하나로 잇는다.
    case paragraph(String)
    case list([MarkdownListItem])
    case code(language: String?, text: String)
    case table(MarkdownTable)
    /// `>` 줄들. 안쪽은 문단 글자로만 본다(줄바꿈 유지).
    case quote(String)
    case rule
}

public struct MarkdownListItem: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)
    }

    public var marker: Marker
    public var text: String
    /// `- [ ]` → false, `- [x]` → true, 체크박스가 아니면 nil.
    public var checked: Bool?
    /// 들여쓰기 단계(공백 2칸 또는 탭 하나 = 1).
    public var depth: Int

    public init(marker: Marker, text: String, checked: Bool? = nil, depth: Int = 0) {
        self.marker = marker
        self.text = text
        self.checked = checked
        self.depth = depth
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case leading, center, trailing
    }

    public var header: [String]
    public var alignments: [Alignment]
    /// 칸 수는 머리에 맞춰 채우거나 자른다.
    public var rows: [[String]]

    public init(header: [String], alignments: [Alignment], rows: [[String]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }
}

/// 한 줄씩 읽는 블록 파서. CommonMark 전부가 아니라 지침 문서에 흔한 문법만 다룬다.
public enum MarkdownParser {

    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                i += 1
            } else if let fence = fence(trimmed) {
                i = parseCode(lines, from: i, fence: fence, into: &blocks)
            } else if let heading = heading(trimmed) {
                blocks.append(heading)
                i += 1
            } else if isRule(trimmed) {
                blocks.append(.rule)
                i += 1
            } else if trimmed.hasPrefix(">") {
                i = parseQuote(lines, from: i, into: &blocks)
            } else if listItem(line) != nil {
                i = parseList(lines, from: i, into: &blocks)
            } else if let table = table(lines, at: i) {
                blocks.append(.table(table.table))
                i = table.next
            } else {
                i = parseParagraph(lines, from: i, into: &blocks)
            }
        }
        return blocks
    }

    /// 제목 목록(목차용): 블록 번호와 함께.
    public static func headings(in blocks: [MarkdownBlock]) -> [(index: Int, level: Int, text: String)] {
        blocks.enumerated().compactMap { index, block in
            if case .heading(let level, let text) = block { (index, level, text) } else { nil }
        }
    }

    // MARK: - 블록

    private static func fence(_ trimmed: String) -> (marker: String, language: String?)? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            if marker == "```", info.contains("`") { return nil }
            return (marker, info.isEmpty ? nil : String(info.split(separator: " ").first ?? ""))
        }
        return nil
    }

    private static func parseCode(_ lines: [String], from start: Int, fence: (marker: String, language: String?), into blocks: inout [MarkdownBlock]) -> Int {
        let indent = lines[start].prefix { $0 == " " }.count
        var body: [String] = []
        var i = start + 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker),
               lines[i].trimmingCharacters(in: .whitespaces).allSatisfy({ String($0) == String(fence.marker.first!) }) {
                i += 1
                break
            }
            // 여는 울타리만큼 들여쓴 것은 걷어 낸다
            var line = Substring(lines[i])
            var removed = 0
            while removed < indent, line.first == " " { line = line.dropFirst(); removed += 1 }
            body.append(String(line))
            i += 1
        }
        blocks.append(.code(language: fence.language, text: body.joined(separator: "\n")))
        return i
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // 닫는 # 줄
        if let range = text.range(of: #"\s+#+$"#, options: .regularExpression) { text.removeSubrange(range) }
        else if text.allSatisfy({ $0 == "#" }) { text = "" }
        return .heading(level: hashes, text: text)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseQuote(_ lines: [String], from start: Int, into blocks: inout [MarkdownBlock]) -> Int {
        var body: [String] = []
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var rest = trimmed.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
            body.append(String(rest))
            i += 1
        }
        blocks.append(.quote(body.joined(separator: "\n")))
        return i
    }

    /// 목록 줄이면 (깊이, 표시, 본문).
    static func listItem(_ line: String) -> MarkdownListItem? {
        var spaces = 0
        var rest = Substring(line)
        while let c = rest.first, c == " " || c == "\t" {
            spaces += c == "\t" ? 2 : 1
            rest = rest.dropFirst()
        }
        let marker: MarkdownListItem.Marker
        if let c = rest.first, "-*+".contains(c), rest.dropFirst().first == " " {
            marker = .bullet
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count), let n = Int(digits) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let d = after.first, d == "." || d == ")", after.dropFirst().first == " " else { return nil }
            marker = .number(n)
            rest = after.dropFirst(2)
        }
        var text = rest.trimmingCharacters(in: .whitespaces)
        var checked: Bool?
        let lower = text.lowercased()
        if lower.hasPrefix("[ ] ") || lower == "[ ]" { checked = false }
        else if lower.hasPrefix("[x] ") || lower == "[x]" { checked = true }
        if checked != nil { text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        return MarkdownListItem(marker: marker, text: text, checked: checked, depth: spaces / 2)
    }

    private static func parseList(_ lines: [String], from start: Int, into blocks: inout [MarkdownBlock]) -> Int {
        var items: [MarkdownListItem] = []
        var i = start
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let item = listItem(line) {
                items.append(item)
                i += 1
            } else if trimmed.isEmpty {
                // 빈 줄 뒤에 목록이 이어지면 같은 목록
                guard i + 1 < lines.count, listItem(lines[i + 1]) != nil else { break }
                i += 1
            } else if line.first == " " || line.first == "\t", !items.isEmpty,
                      fence(trimmed) == nil {
                // 들여쓴 이어지는 줄은 앞 항목에 붙인다
                items[items.count - 1].text += " " + trimmed
                i += 1
            } else {
                break
            }
        }
        blocks.append(.list(items))
        return i
    }

    private static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") { trimmed.removeLast() }
        var result: [String] = []
        var current = ""
        var escaped = false
        var inCode = false
        for c in trimmed {
            if escaped { current.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "`" { inCode.toggle() }
            if c == "|" && !inCode {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func alignments(_ line: String) -> [MarkdownTable.Alignment]? {
        guard line.contains("-") else { return nil }
        let parts = cells(line)
        var result: [MarkdownTable.Alignment] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0 == "-" || $0 == ":" }), part.contains("-") else { return nil }
            let left = part.hasPrefix(":"), right = part.hasSuffix(":")
            result.append(left && right ? .center : right ? .trailing : .leading)
        }
        return result
    }

    private static func table(_ lines: [String], at start: Int) -> (table: MarkdownTable, next: Int)? {
        guard start + 1 < lines.count, lines[start].contains("|"),
              let aligns = alignments(lines[start + 1]) else { return nil }
        let header = cells(lines[start])
        guard header.count == aligns.count else { return nil }
        var rows: [[String]] = []
        var i = start + 2
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            var row = cells(lines[i])
            if row.count < header.count { row += Array(repeating: "", count: header.count - row.count) }
            rows.append(Array(row.prefix(header.count)))
            i += 1
        }
        return (MarkdownTable(header: header, alignments: aligns, rows: rows), i)
    }

    private static func parseParagraph(_ lines: [String], from start: Int, into blocks: inout [MarkdownBlock]) -> Int {
        var body: [String] = [lines[start].trimmingCharacters(in: .whitespaces)]
        var i = start + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || fence(trimmed) != nil || heading(trimmed) != nil || isRule(trimmed)
                || trimmed.hasPrefix(">") || listItem(lines[i]) != nil || table(lines, at: i) != nil {
                break
            }
            body.append(trimmed)
            i += 1
        }
        blocks.append(.paragraph(body.joined(separator: " ")))
        return i
    }
}
