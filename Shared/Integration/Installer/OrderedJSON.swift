import Foundation

/// 키 순서와 숫자 원문을 지키는 JSON 값. 설치기가 사용자 설정(`settings.json`·`hooks.json`)을 고칠 때
/// 손대지 않은 부분이 그대로 남게 한다(`JSONSerialization`은 키 순서를 잃는다).
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// 원문 그대로(`2`, `1.50`, `-3e2`)
    case number(String)
    case bool(Bool)
    case null

    public static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.array(a), .array(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.bool(a), .bool(b)): a == b
        case (.null, .null): true
        default: false
        }
    }

    // MARK: - 읽기 도움

    public subscript(key: String) -> OrderedJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.last(where: { $0.0 == key })?.1
    }

    public var objectPairs: [(String, OrderedJSON)]? {
        if case .object(let pairs) = self { return pairs }
        return nil
    }

    public var arrayValue: [OrderedJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// 객체에서 키의 값을 바꾼다. 있던 키면 그 자리에, 없던 키면 끝에. nil이면 지운다.
    public func setting(_ key: String, _ value: OrderedJSON?) -> OrderedJSON {
        guard case .object(var pairs) = self else { return self }
        if let index = pairs.firstIndex(where: { $0.0 == key }) {
            if let value { pairs[index].1 = value } else { pairs.remove(at: index) }
        } else if let value {
            pairs.append((key, value))
        }
        return .object(pairs)
    }

    // MARK: - 해석

    public enum ParseError: Error, Equatable {
        case invalid(offset: Int)
    }

    public static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: [UInt8](data))
        parser.skipSpace()
        let value = try parser.value(depth: 0)
        parser.skipSpace()
        guard parser.index == parser.bytes.count else { throw ParseError.invalid(offset: parser.index) }
        return value
    }

    public static func parse(_ text: String) throws -> OrderedJSON {
        try parse(Data(text.utf8))
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        func fail() -> ParseError { .invalid(offset: index) }

        mutating func expect(_ literal: String) throws {
            let lit = Array(literal.utf8)
            guard index + lit.count <= bytes.count, Array(bytes[index..<index + lit.count]) == lit else { throw fail() }
            index += lit.count
        }

        mutating func value(depth: Int) throws -> OrderedJSON {
            guard depth < 512, index < bytes.count else { throw fail() }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try number())
            }
        }

        mutating func object(depth: Int) throws -> OrderedJSON {
            index += 1
            var pairs: [(String, OrderedJSON)] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail() }
                let key = try string()
                skipSpace()
                try expect(":")
                skipSpace()
                let item = try value(depth: depth + 1)
                // 겹친 키: 마지막 값을 처음 자리에(Python json.loads·JSON.parse와 같다)
                if let at = pairs.firstIndex(where: { $0.0 == key }) { pairs[at].1 = item } else { pairs.append((key, item)) }
                skipSpace()
                guard index < bytes.count else { throw fail() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                throw fail()
            }
        }

        mutating func array(depth: Int) throws -> OrderedJSON {
            index += 1
            var items: [OrderedJSON] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value(depth: depth + 1))
                skipSpace()
                guard index < bytes.count else { throw fail() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw fail()
            }
        }

        mutating func number() throws -> String {
            let start = index
            func digits() -> Int {
                let s = index
                while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
                return index - s
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw fail() }
            if bytes[index] == UInt8(ascii: "0") { index += 1 } else if digits() == 0 { throw fail() }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw fail() }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw fail() }
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count,
                  let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else { throw fail() }
            index += 4
            return value
        }

        mutating func string() throws -> String {
            index += 1
            var out = [UInt8]()
            while true {
                guard index < bytes.count else { throw fail() }
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") { index += 1; break }
                if byte < 0x20 { throw fail() }
                if byte != UInt8(ascii: "\\") { out.append(byte); index += 1; continue }
                index += 1
                guard index < bytes.count else { throw fail() }
                let esc = bytes[index]
                index += 1
                switch esc {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800...0xDBFF).contains(scalar), index + 6 <= bytes.count,
                       bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                        let save = index
                        index += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            index = save
                        }
                    }
                    // 짝 없는 서로게이트는 U+FFFD로(Swift 문자열에 담을 수 없다)
                    let unicode = Unicode.Scalar(scalar) ?? "\u{FFFD}"
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default: throw fail()
                }
            }
            guard let text = String(bytes: out, encoding: .utf8) else { throw fail() }
            return text
        }
    }

    // MARK: - 쓰기

    /// 쓰기 꼴. 기본은 Python `json.dumps(indent=2, ensure_ascii=False)`·JS `JSON.stringify(v, null, 2)`와 같은
    /// 바이트를 낸다(둘은 이 범위에서 같다).
    public struct Style: Equatable, Sendable {
        public var indent: String
        /// true면 숫자를 Python이 다시 쓰는 꼴로(정수는 그대로, 실수는 `repr`). false면 원문 그대로.
        public var pythonNumbers: Bool
        public init(indent: String = "  ", pythonNumbers: Bool = false) {
            self.indent = indent
            self.pythonNumbers = pythonNumbers
        }
        public static let python = Style(indent: "  ", pythonNumbers: true)
    }

    public func serialized(style: Style = Style()) -> String {
        var out = ""
        write(into: &out, level: 0, style: style)
        return out
    }

    private func write(into out: inout String, level: Int, style: Style) {
        switch self {
        case .object(let pairs):
            guard !pairs.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (i, pair) in pairs.enumerated() {
                out += String(repeating: style.indent, count: level + 1)
                out += Self.quoted(pair.0) + ": "
                pair.1.write(into: &out, level: level + 1, style: style)
                out += i == pairs.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: style.indent, count: level) + "}"
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += String(repeating: style.indent, count: level + 1)
                item.write(into: &out, level: level + 1, style: style)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: style.indent, count: level) + "]"
        case .string(let value): out += Self.quoted(value)
        case .number(let raw): out += style.pythonNumbers ? Self.pythonNumber(raw) : raw
        case .bool(let value): out += value ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Python이 `json.loads` → `json.dumps`로 다시 쓰는 숫자 꼴.
    static func pythonNumber(_ raw: String) -> String {
        let isInteger = !raw.contains(where: { $0 == "." || $0 == "e" || $0 == "E" })
        if isInteger {
            return raw == "-0" ? "0" : raw
        }
        guard let value = Double(raw) else { return raw }
        if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
        return "\(value)"
    }
}
