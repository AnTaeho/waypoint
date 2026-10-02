import Foundation

/// Codex 설치기가 `config.toml`에서 알아야 하는 것만 읽는 작은 TOML 해석기.
/// 전체 값을 만들지 않고 「키 경로 → 값」으로 펼친다. 구조가 틀리면(키 없는 줄, 닫히지 않은 문자열·배열,
/// 겹친 키·표) 오류를 낸다. Python `tomllib`가 받아들이는 문서를 거절하지 않는 것이 목표이고,
/// `tomllib`가 거절하는 모든 문서를 잡아내지는 못한다(날짜·숫자 꼴은 느슨하게 본다).
struct MiniTOML {
    enum Leaf: Equatable {
        case string(String)
        /// 문자열이 아닌 값(숫자·불·날짜·배열)의 원문
        case other(String)
    }

    struct ParseError: Error, Equatable {
        let line: Int
    }

    /// 펼친 값. 키 경로 → 값
    private(set) var entries: [[String]: Leaf] = [:]
    /// 정의된 표(머리 `[a.b]`, 인라인 표, 점 키로 생긴 표)
    private(set) var tables: Set<[String]> = []
    private var explicitTables: Set<[String]> = []

    init(_ text: String) throws {
        var scanner = Scanner(chars: Array(text.unicodeScalars))
        var current: [String] = []
        var arrayCounts: [[String]: Int] = [:]
        while true {
            scanner.skipBlankLinesAndComments()
            guard !scanner.atEnd else { break }
            if scanner.peek == "[" {
                let isArray = scanner.peek(at: 1) == "["
                scanner.advance(isArray ? 2 : 1)
                scanner.skipInlineSpace()
                let key = try scanner.key()
                scanner.skipInlineSpace()
                guard scanner.consume("]"), !isArray || scanner.consume("]") else { throw scanner.error() }
                try scanner.endOfLine()
                if isArray {
                    let index = arrayCounts[key, default: 0]
                    arrayCounts[key] = index + 1
                    current = key + ["[\(index)]"]
                } else {
                    guard !explicitTables.contains(key), entries[key] == nil else { throw scanner.error() }
                    explicitTables.insert(key)
                    current = key
                }
                markTables(current)
            } else {
                let key = try scanner.key()
                scanner.skipInlineSpace()
                guard scanner.consume("=") else { throw scanner.error() }
                scanner.skipInlineSpace()
                try value(at: current + key, scanner: &scanner)
                try scanner.endOfLine()
            }
        }
    }

    private mutating func markTables(_ path: [String]) {
        for length in 1...max(path.count, 1) where length <= path.count {
            tables.insert(Array(path.prefix(length)))
        }
    }

    private mutating func value(at path: [String], scanner: inout Scanner) throws {
        guard entries[path] == nil, !tables.contains(path) else { throw scanner.error() }
        if path.count > 1 { markTables(Array(path.dropLast())) }
        switch scanner.peek {
        case "\"", "'":
            entries[path] = .string(try scanner.string())
        case "[":
            let start = scanner.index
            try scanner.skipArray()
            entries[path] = .other(scanner.text(from: start))
        case "{":
            scanner.advance(1)
            markTables(path)
            scanner.skipInlineSpace()
            if scanner.consume("}") { return }
            while true {
                scanner.skipInlineSpace()
                let key = try scanner.key()
                scanner.skipInlineSpace()
                guard scanner.consume("=") else { throw scanner.error() }
                scanner.skipInlineSpace()
                try value(at: path + key, scanner: &scanner)
                scanner.skipInlineSpace()
                if scanner.consume(",") { continue }
                if scanner.consume("}") { return }
                throw scanner.error()
            }
        default:
            entries[path] = .other(try scanner.scalar())
        }
    }

    // MARK: - 묻기

    /// 경로나 그 아래에 무엇이든 있는가
    func contains(_ path: [String]) -> Bool {
        tables.contains(path) || entries.keys.contains { $0.starts(with: path) }
    }

    /// 경로 바로 아래의 값(키 → 값). 하위 표가 있으면 nil
    func flatTable(_ path: [String]) -> [String: Leaf]? {
        guard tables.contains(path) else { return nil }
        if tables.contains(where: { $0.count > path.count && $0.starts(with: path) }) { return nil }
        var result: [String: Leaf] = [:]
        for (key, leaf) in entries where key.count == path.count + 1 && key.starts(with: path) {
            result[key[path.count]] = leaf
        }
        return result
    }

    func leaf(_ path: [String]) -> Leaf? { entries[path] }

    // MARK: - 글자 읽기

    private struct Scanner {
        let chars: [Unicode.Scalar]
        var index = 0
        var line = 1

        var atEnd: Bool { index >= chars.count }
        var peek: Unicode.Scalar? { atEnd ? nil : chars[index] }
        func peek(at offset: Int) -> Unicode.Scalar? { index + offset < chars.count ? chars[index + offset] : nil }
        func error() -> ParseError { ParseError(line: line) }

        mutating func advance(_ count: Int) {
            for _ in 0..<count where !atEnd {
                if chars[index] == "\n" { line += 1 }
                index += 1
            }
        }

        mutating func consume(_ char: Unicode.Scalar) -> Bool {
            guard peek == char else { return false }
            advance(1)
            return true
        }

        func text(from start: Int) -> String {
            var out = String.UnicodeScalarView()
            out.append(contentsOf: chars[start..<index])
            return String(out)
        }

        mutating func skipInlineSpace() {
            while let c = peek, c == " " || c == "\t" { advance(1) }
        }

        mutating func skipComment() {
            guard peek == "#" else { return }
            while let c = peek, c != "\n" { advance(1) }
        }

        mutating func skipBlankLinesAndComments() {
            while true {
                skipInlineSpace()
                skipComment()
                if peek == "\n" { advance(1); continue }
                if peek == "\r", peek(at: 1) == "\n" { advance(2); continue }
                return
            }
        }

        /// 값·머리 뒤: 공백, 주석, 줄 끝(또는 문서 끝)만
        mutating func endOfLine() throws {
            skipInlineSpace()
            skipComment()
            if atEnd { return }
            if consume("\n") { return }
            if peek == "\r", peek(at: 1) == "\n" { advance(2); return }
            throw error()
        }

        static func isBare(_ c: Unicode.Scalar) -> Bool {
            ("A"..."Z").contains(c) || ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "_" || c == "-"
        }

        mutating func key() throws -> [String] {
            var parts: [String] = []
            while true {
                skipInlineSpace()
                if peek == "\"" || peek == "'" {
                    guard peek(at: 1) != peek || peek(at: 2) != peek else { throw error() } // 여러 줄 문자열은 키가 될 수 없다
                    parts.append(try string())
                } else {
                    let start = index
                    while let c = peek, Self.isBare(c) { advance(1) }
                    guard index > start else { throw error() }
                    parts.append(text(from: start))
                }
                skipInlineSpace()
                if !consume(".") { return parts }
            }
        }

        mutating func string() throws -> String {
            guard let quote = peek else { throw error() }
            let literal = quote == "'"
            let multi = peek(at: 1) == quote && peek(at: 2) == quote
            advance(multi ? 3 : 1)
            if multi {
                // 여는 따옴표 바로 뒤 줄바꿈은 값에 넣지 않는다
                if peek == "\n" { advance(1) } else if peek == "\r", peek(at: 1) == "\n" { advance(2) }
            }
            var out = String.UnicodeScalarView()
            while true {
                guard let c = peek else { throw error() }
                if c == quote {
                    if !multi { advance(1); return String(out) }
                    if peek(at: 1) == quote, peek(at: 2) == quote {
                        // 닫는 따옴표 앞에 따옴표가 한두 개 더 붙을 수 있다(`""""`·`"""""`)
                        var extra = 0
                        while extra < 2, peek(at: 3 + extra) == quote { extra += 1 }
                        for _ in 0..<extra { out.append(quote) }
                        advance(3 + extra)
                        return String(out)
                    }
                    out.append(c)
                    advance(1)
                    continue
                }
                if c == "\n" && !multi { throw error() }
                if c == "\\" && !literal {
                    advance(1)
                    guard let e = peek else { throw error() }
                    switch e {
                    case "b": out.append("\u{08}"); advance(1)
                    case "t": out.append("\t"); advance(1)
                    case "n": out.append("\n"); advance(1)
                    case "f": out.append("\u{0C}"); advance(1)
                    case "r": out.append("\r"); advance(1)
                    case "e": out.append("\u{1B}"); advance(1)
                    case "\"": out.append("\""); advance(1)
                    case "\\": out.append("\\"); advance(1)
                    case "u", "U", "x":
                        let count = e == "u" ? 4 : e == "U" ? 8 : 2
                        advance(1)
                        guard index + count <= chars.count else { throw error() }
                        var hex = String.UnicodeScalarView()
                        hex.append(contentsOf: chars[index..<index + count])
                        guard let value = UInt32(String(hex), radix: 16), let scalar = Unicode.Scalar(value) else {
                            throw error()
                        }
                        out.append(scalar)
                        advance(count)
                    case " ", "\t", "\n", "\r":
                        // 여러 줄 문자열의 줄 끝 역슬래시: 다음 공백·줄바꿈을 모두 건너뛴다
                        guard multi else { throw error() }
                        let save = index
                        while let w = peek, w == " " || w == "\t" { advance(1) }
                        guard peek == "\n" || (peek == "\r" && peek(at: 1) == "\n") else { index = save; throw error() }
                        while let w = peek, w == " " || w == "\t" || w == "\n" || w == "\r" { advance(1) }
                    default:
                        throw error()
                    }
                    continue
                }
                out.append(c)
                advance(1)
            }
        }

        /// 배열을 건너뛴다(안의 문자열·인라인 표·주석·줄바꿈 포함)
        mutating func skipArray() throws {
            guard consume("[") else { throw error() }
            var expectValue = true
            while true {
                skipBlankLinesAndComments()
                guard let c = peek else { throw error() }
                if c == "]" { advance(1); return }
                if c == "," {
                    guard !expectValue else { throw error() }
                    advance(1); expectValue = true; continue
                }
                guard expectValue else { throw error() }
                switch c {
                case "\"", "'": _ = try string()
                case "[": try skipArray()
                case "{": try skipInlineTable()
                default: _ = try scalar()
                }
                expectValue = false
            }
        }

        mutating func skipInlineTable() throws {
            guard consume("{") else { throw error() }
            skipInlineSpace()
            if consume("}") { return }
            while true {
                skipInlineSpace()
                _ = try key()
                skipInlineSpace()
                guard consume("=") else { throw error() }
                skipInlineSpace()
                switch peek {
                case "\"", "'": _ = try string()
                case "[": try skipArray()
                case "{": try skipInlineTable()
                default: _ = try scalar()
                }
                skipInlineSpace()
                if consume(",") { continue }
                if consume("}") { return }
                throw error()
            }
        }

        static let scalarPattern = try! NSRegularExpression(pattern: """
            ^(true|false|[+-]?(inf|nan)|[+-]?[0-9][0-9_]*(\\.[0-9][0-9_]*)?([eE][+-]?[0-9][0-9_]*)?\
            |0x[0-9A-Fa-f][0-9A-Fa-f_]*|0o[0-7][0-7_]*|0b[01][01_]*\
            |[0-9]{4}-[0-9]{2}-[0-9]{2}([Tt ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\\.[0-9]+)?)?([Zz]|[+-][0-9]{2}:[0-9]{2})?)?\
            |[0-9]{2}:[0-9]{2}(:[0-9]{2}(\\.[0-9]+)?)?)$
            """)

        /// 숫자·불·날짜. 날짜와 시각 사이 공백 하나는 함께 읽는다.
        mutating func scalar() throws -> String {
            let start = index
            func stop(_ c: Unicode.Scalar) -> Bool {
                c == " " || c == "\t" || c == "\n" || c == "\r" || c == "," || c == "]" || c == "}" || c == "#"
            }
            while let c = peek, !stop(c) { advance(1) }
            var token = text(from: start)
            if token.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
               peek == " ", let next = peek(at: 1), ("0"..."9").contains(next) {
                advance(1)
                while let c = peek, !stop(c) { advance(1) }
                token = text(from: start)
            }
            let range = NSRange(token.startIndex..., in: token)
            guard !token.isEmpty, Self.scalarPattern.firstMatch(in: token, range: range) != nil else { throw error() }
            return token
        }
    }
}
