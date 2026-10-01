import Foundation

/// 원문 한 줄의 바이트 위치. `\n`으로 나누고, 바로 앞 `\r`은 줄 끝 개행에 넣는다.
struct GuidanceLine: Hashable, Sendable {
    var start: Int
    /// 줄 끝 개행 앞
    var contentEnd: Int
    /// 줄 끝 개행 뒤(마지막 줄에 개행이 없으면 `contentEnd`와 같다)
    var end: Int
}

/// 바이트로 읽은 원문과 줄 표.
struct GuidanceLines {
    let bytes: [UInt8]
    let lines: [GuidanceLine]
    /// 줄 내용(개행 제외)
    let contents: [String]

    init(_ text: String) {
        let bytes = Array(text.utf8)
        var lines: [GuidanceLine] = []
        var start = 0
        for (i, byte) in bytes.enumerated() where byte == 0x0A {
            let contentEnd = i > start && bytes[i - 1] == 0x0D ? i - 1 : i
            lines.append(GuidanceLine(start: start, contentEnd: contentEnd, end: i + 1))
            start = i + 1
        }
        if start < bytes.count {
            lines.append(GuidanceLine(start: start, contentEnd: bytes.count, end: bytes.count))
        }
        self.bytes = bytes
        self.lines = lines
        self.contents = lines.map { String(decoding: bytes[$0.start..<$0.contentEnd], as: UTF8.self) }
    }

    var count: Int { lines.count }

    func string(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    func isBlank(_ index: Int) -> Bool {
        contents[index].allSatisfy { $0 == " " || $0 == "\t" }
    }

    func trimmed(_ index: Int) -> String {
        contents[index].trimmingCharacters(in: .whitespaces)
    }

    /// 앞 공백 칸 수(탭은 다음 4의 배수까지)
    func indent(_ index: Int) -> Int {
        var column = 0
        for c in contents[index].unicodeScalars {
            if c == " " { column += 1 }
            else if c == "\t" { column += 4 - column % 4 }
            else { break }
        }
        return column
    }

    /// 앞 공백 글자들
    func leadingWhitespace(_ index: Int) -> Substring {
        contents[index].prefix { $0 == " " || $0 == "\t" }
    }

    /// 줄 범위 `first...last`를 항목 바탕으로
    func item(
        kind: GuidanceItemKind, first: Int, last: Int, section: [String], display: String,
        marker: String? = nil, children: [GuidanceItem] = []
    ) -> GuidanceItem {
        let range = lines[first].start..<lines[last].end
        let content = lines[first].start..<lines[last].contentEnd
        return GuidanceItem(
            id: [], kind: kind, range: range, contentRange: content, lines: first..<(last + 1),
            text: string(content), terminator: string(lines[last].contentEnd..<lines[last].end),
            section: section, display: display, marker: marker, children: children
        )
    }
}
