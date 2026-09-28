import Foundation

/// 줄 단위 차이(가장 긴 공통 부분열). 충돌 비교 화면의 추가·삭제 줄 강조에 쓴다.
public enum LineDiff {

    public enum Kind: Equatable, Sendable {
        case same, removed, added
    }

    public struct Line: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// 표를 만들 줄 수 곱의 상한. 넘으면 앞뒤 공통 줄만 맞추고 가운데는 전부 삭제+추가로 본다.
    public static let cellLimit = 4_000_000

    /// `old` → `new`. 같은 줄, 지운 줄(old에만), 더한 줄(new에만)을 순서대로.
    public static func diff(_ old: [String], _ new: [String]) -> [Line] {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        let a = Array(old[prefix..<(old.count - suffix)])
        let b = Array(new[prefix..<(new.count - suffix)])
        var result = old[..<prefix].map { Line(.same, $0) }
        if a.count * b.count > cellLimit {
            result += a.map { Line(.removed, $0) } + b.map { Line(.added, $0) }
        } else {
            result += middle(a, b)
        }
        result += old[(old.count - suffix)...].map { Line(.same, $0) }
        return result
    }

    /// 문자열을 줄로 나눠 비교한다. 끝 줄바꿈 하나는 빈 줄로 세지 않는다.
    public static func diff(_ old: String, _ new: String) -> [Line] {
        diff(lines(old), lines(new))
    }

    public static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static func middle(_ a: [String], _ b: [String]) -> [Line] {
        let n = a.count, m = b.count
        guard n > 0 || m > 0 else { return [] }
        // lcs[i][j] = a[i...]과 b[j...]의 공통 부분열 길이
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                result.append(Line(.same, a[i])); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                result.append(Line(.removed, a[i])); i += 1
            } else {
                result.append(Line(.added, b[j])); j += 1
            }
        }
        result += a[i...].map { Line(.removed, $0) }
        result += b[j...].map { Line(.added, $0) }
        return result
    }
}
