import Foundation

/// Codex 명령 규칙(`*.rules`, Starlark)을 규칙 하나씩 나눈다. 보통 한 줄이 한 규칙이고,
/// 괄호가 닫히지 않으면 닫힐 때까지 다음 줄을 묶는다. 문자열 안의 괄호·`#`은 세지 않는다.
/// 주석 줄과 빈 줄은 항목이 아니다(그대로 남는다).
struct GuidanceRulesSplitter {
    let text: GuidanceLines
    private(set) var reasons: [String] = []

    init(_ text: GuidanceLines) {
        self.text = text
    }

    static func isComment(_ trimmed: String) -> Bool { trimmed.hasPrefix("#") }

    mutating func split() -> [GuidanceItem] {
        var items: [GuidanceItem] = []
        var state = Scanner()
        var start: Int?
        for index in 0..<text.count {
            let trimmed = text.trimmed(index)
            if start == nil {
                if trimmed.isEmpty || Self.isComment(trimmed) { continue }
                start = index
            }
            state.feed(text.contents[index])
            if state.broken {
                note("괄호 짝이 맞지 않는 규칙")
                return items
            }
            if state.isBalanced, let first = start {
                let display = text.contents[first...index].map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                items.append(text.item(kind: .rule, first: first, last: index, section: [], display: display))
                start = nil
            }
        }
        if start != nil { note("괄호가 닫히지 않은 규칙") }
        return items
    }

    private mutating func note(_ reason: String) {
        if !reasons.contains(reason) { reasons.append(reason) }
    }

    /// 괄호 깊이와 여러 줄 문자열(`"""`·`'''`) 상태
    struct Scanner {
        var depth = 0
        var triple: String?
        var broken = false

        var isBalanced: Bool { depth == 0 && triple == nil }

        mutating func feed(_ line: String) {
            let chars = Array(line)
            var i = 0
            var quote: Character?
            while i < chars.count {
                let c = chars[i]
                if let open = triple {
                    if c == "\\" { i += 2; continue }
                    if String(chars[i..<min(i + 3, chars.count)]) == open { triple = nil; i += 3; continue }
                    i += 1
                    continue
                }
                if let q = quote {
                    if c == "\\" { i += 2; continue }
                    if c == q { quote = nil }
                    i += 1
                    continue
                }
                switch c {
                case "\"", "'":
                    let three = String(repeating: String(c), count: 3)
                    if String(chars[i..<min(i + 3, chars.count)]) == three {
                        triple = three
                        i += 3
                        continue
                    }
                    quote = c
                case "#":
                    return
                case "(", "[", "{":
                    depth += 1
                case ")", "]", "}":
                    depth -= 1
                    if depth < 0 { broken = true; return }
                default:
                    break
                }
                i += 1
            }
            // 한 줄 문자열은 줄 끝에서 끝난다
        }
    }
}
