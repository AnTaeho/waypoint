import Foundation

/// Markdown 지침을 항목 블록으로 나눈다. 줄 판정(코드 울타리·절 머리·구분선·목록·표)은
/// 보기 화면의 `MarkdownParser`와 같은 것을 써서 화면에 보이는 모양과 항목이 어긋나지 않게 한다.
struct GuidanceMarkdownSplitter {
    struct Block {
        var kind: GuidanceItemKind
        var first: Int
        var last: Int
        var marker: String?
        var headingLevel = 0
        var headingText = ""
        var children: [Block] = []
    }

    /// 목록이 이보다 깊으면 애매한 문서로 본다(0부터 세어 4 = 5단).
    static let maxListDepth = 4

    let text: GuidanceLines
    private(set) var reasons: [String] = []
    private var tabIndented = false
    private var spaceIndented = false

    init(_ text: GuidanceLines) {
        self.text = text
    }

    mutating func note(_ reason: String) {
        if !reasons.contains(reason) { reasons.append(reason) }
    }

    /// 맨 위 항목. 문제가 있으면 `reasons`에 이유를 남긴다.
    mutating func split() -> [GuidanceItem] {
        var start = 0
        var items: [GuidanceItem] = []
        if let close = Self.frontmatterClose(text) {
            let inner = close > 1 ? text.contents[1..<close].joined(separator: "\n") : ""
            items.append(text.item(kind: .frontmatter, first: 0, last: close, section: [], display: inner))
            start = close + 1
        } else if text.count > 0, text.trimmed(0) == "---" {
            note("frontmatter가 닫히지 않음")
        }
        let blocks = scan(start, text.count, depth: 0)
        if tabIndented && spaceIndented { note("목록 들여쓰기에 탭과 공백이 섞임") }

        var stack: [(level: Int, text: String)] = []
        for block in blocks {
            if block.kind == .heading {
                while let top = stack.last, top.level >= block.headingLevel { stack.removeLast() }
                items.append(item(block, section: stack.map(\.text)))
                stack.append((block.headingLevel, block.headingText))
            } else {
                items.append(item(block, section: stack.map(\.text)))
            }
        }
        return items
    }

    /// 첫 줄이 `---`이고 뒤에 닫는 `---`가 있으면 그 줄 번호(`GuidanceText.splitHeader`와 같은 판정)
    static func frontmatterClose(_ text: GuidanceLines) -> Int? {
        guard text.count > 1, text.trimmed(0) == "---" else { return nil }
        return (1..<text.count).first { text.trimmed($0) == "---" }
    }

    // MARK: - 블록 찾기

    private mutating func scan(_ lo: Int, _ hi: Int, depth: Int) -> [Block] {
        var blocks: [Block] = []
        var i = lo
        while i < hi {
            if text.isBlank(i) { i += 1; continue }
            let trimmed = text.trimmed(i)
            if let fence = MarkdownParser.fence(trimmed) {
                let last = closingFence(after: i, hi, marker: fence.marker)
                blocks.append(Block(kind: .code, first: i, last: last))
                i = last + 1
            } else if case .heading(let level, let title)? = MarkdownParser.heading(trimmed) {
                blocks.append(Block(kind: .heading, first: i, last: i, headingLevel: level, headingText: title))
                i += 1
            } else if MarkdownParser.isRule(trimmed) || Self.isLineComment(trimmed) {
                i += 1
            } else if trimmed.hasPrefix(">") {
                var j = i + 1
                while j < hi, text.trimmed(j).hasPrefix(">") { j += 1 }
                blocks.append(Block(kind: .quote, first: i, last: j - 1))
                i = j
            } else if MarkdownParser.listItem(text.contents[i]) != nil {
                let block = listItem(at: i, hi, depth: depth)
                blocks.append(block)
                i = block.last + 1
            } else if isTable(at: i, hi) {
                blocks.append(Block(kind: .tableHeader, first: i, last: i + 1))
                var j = i + 2
                while j < hi, !text.isBlank(j), text.contents[j].contains("|") {
                    blocks.append(Block(kind: .tableRow, first: j, last: j))
                    j += 1
                }
                i = j
            } else {
                var j = i + 1
                while j < hi, !interruptsParagraph(j, hi) { j += 1 }
                if (i..<j).contains(where: { Self.isHTMLStart(text.trimmed($0)) }) { note("HTML 블록") }
                blocks.append(Block(kind: .paragraph, first: i, last: j - 1))
                i = j
            }
        }
        return blocks
    }

    /// 닫는 울타리 줄. 없으면 애매함을 남기고 범위 끝 줄.
    private mutating func closingFence(after start: Int, _ hi: Int, marker: String) -> Int {
        let char = marker.first!
        for j in (start + 1)..<max(start + 1, hi) {
            let trimmed = text.trimmed(j)
            if trimmed.hasPrefix(marker), trimmed.allSatisfy({ $0 == char }) { return j }
        }
        note("닫히지 않은 코드 블록")
        return hi - 1
    }

    /// 목록 항목: 표시 줄 + 그보다 깊이 들여쓴 줄(사이 빈 줄 포함). 들여쓰지 않은 줄을 만나면 끝난다.
    /// 안에 연 코드 울타리는 들여쓰기와 상관없이 닫는 줄까지 이 항목에 넣는다.
    private mutating func listItem(at start: Int, _ hi: Int, depth: Int) -> Block {
        let indent = text.indent(start)
        let whitespace = text.leadingWhitespace(start)
        if whitespace.contains("\t") { tabIndented = true }
        if whitespace.contains(" ") { spaceIndented = true }
        if depth > Self.maxListDepth { note("목록 중첩이 \(Self.maxListDepth + 1)단을 넘음") }

        var last = start
        var j = start + 1
        while j < hi {
            if text.isBlank(j) {
                var k = j
                while k < hi, text.isBlank(k) { k += 1 }
                guard k < hi, text.indent(k) > indent else { break }
                j = k
                continue
            }
            guard text.indent(j) > indent else { break }
            if let fence = MarkdownParser.fence(text.trimmed(j)) {
                last = closingFence(after: j, hi, marker: fence.marker)
            } else {
                last = j
            }
            j = last + 1
        }
        let body = start + 1 <= last ? scan(start + 1, last + 1, depth: depth + 1) : []
        let marker = Self.marker(text.contents[start])
        let numbered = marker.first?.isNumber == true
        return Block(
            kind: numbered ? .numbered : .bullet, first: start, last: last, marker: marker,
            children: body.filter { $0.kind == .bullet || $0.kind == .numbered }
        )
    }

    private func isTable(at i: Int, _ hi: Int) -> Bool {
        i + 1 < hi && text.contents[i].contains("|") && MarkdownParser.table(text.contents, at: i) != nil
    }

    /// 보기 화면의 문단 끝 판정과 같다.
    private func interruptsParagraph(_ j: Int, _ hi: Int) -> Bool {
        let trimmed = text.trimmed(j)
        return trimmed.isEmpty || MarkdownParser.fence(trimmed) != nil || MarkdownParser.heading(trimmed) != nil
            || MarkdownParser.isRule(trimmed) || trimmed.hasPrefix(">")
            || MarkdownParser.listItem(text.contents[j]) != nil || isTable(at: j, hi)
    }

    /// 한 줄 안에서 열고 닫는 HTML 주석 하나(`<!-- … -->`). 구분선처럼 항목 밖 줄로 둔다.
    /// 문단에 붙어 있거나 여러 줄에 걸친 주석은 여전히 HTML 블록이다.
    static func isLineComment(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"), trimmed.count >= 7 else { return false }
        return trimmed.dropFirst(4).dropLast(3).range(of: "-->") == nil
    }

    static func isHTMLStart(_ trimmed: String) -> Bool {
        guard trimmed.first == "<", let next = trimmed.dropFirst().first else { return false }
        return next.isLetter || next == "!" || next == "/" || next == "?"
    }

    static func marker(_ line: String) -> String {
        let rest = line.drop { $0 == " " || $0 == "\t" }
        if let c = rest.first, "-*+".contains(c) { return String(c) }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        let delimiter = rest.dropFirst(digits.count).first.map(String.init) ?? ""
        return String(digits) + delimiter
    }

    // MARK: - 항목 만들기

    private func item(_ block: Block, section: [String]) -> GuidanceItem {
        let children = block.children.map { item($0, section: section) }
        return text.item(
            kind: block.kind, first: block.first, last: block.last, section: section,
            display: display(block), marker: block.marker, children: children
        )
    }

    private func display(_ block: Block) -> String {
        let lines = block.first...block.last
        switch block.kind {
        case .heading:
            return block.headingText
        case .bullet, .numbered:
            let childLines = Set(block.children.flatMap { Array($0.first...$0.last) })
            var parts: [String] = []
            for index in lines where !childLines.contains(index) && !text.isBlank(index) {
                if index == block.first {
                    let item = MarkdownParser.listItem(text.contents[index])
                    let box = item?.checked.map { $0 ? "[x] " : "[ ] " } ?? ""
                    parts.append(box + (item?.text ?? text.trimmed(index)))
                } else {
                    parts.append(text.trimmed(index))
                }
            }
            return parts.joined(separator: " ")
        case .code:
            guard block.last > block.first else { return "" }
            return text.contents[(block.first + 1)..<block.last].joined(separator: "\n")
        case .quote:
            return lines.map { index in
                var rest = text.trimmed(index).dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
                return String(rest)
            }.joined(separator: "\n")
        case .paragraph:
            return lines.map { text.trimmed($0) }.joined(separator: " ")
        default:
            return text.trimmed(block.first)
        }
    }
}
