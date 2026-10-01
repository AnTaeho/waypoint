import Foundation

/// 셸 명령이 검증 명령(테스트·빌드)인지, 그 결과를 종료 코드만으로 믿을 수 있는지 판정한다(SPEC 5장 「검증 근거」).
/// 순수 함수. 훅(`HookProcessor`)과 MCP `card_evidence`가 같이 쓴다.
public enum VerificationCommand {

    /// 검증 명령 패턴. 훅 스크립트의 outbox 필터(`waypoint-hook.sh`의 `verify_pattern`)와 **바이트 단위로 같아야 한다**
    /// (`OutboxTrimTests`가 비교한다). 두 정규식 엔진(Swift Regex, jq/Oniguruma)에 공통인 문법만 쓴다.
    /// 명령의 처음이나 `;` `&` `|` `(` 줄바꿈 뒤에서, 환경 변수 대입·`time` 등의 앞말을 건너뛰고 아래로 시작해야 한다.
    /// 늘릴 때는 스크립트의 같은 줄도 고친다.
    public static let pattern = #"(^|[;&|(\n])\s*([A-Za-z_][A-Za-z0-9_]*=\S*\s+)*((time|env|nice|command|exec)\s+|timeout\s+\S+\s+)*((uv|poetry|pipenv|hatch)\s+run\s+)?(swift\s+(test|build)\b|xcodebuild\b[^;&|\n]*\b(test|build|build-for-testing|test-without-building)\b|(npm|pnpm|yarn|bun)\s+(run\s+)?test\b|(npx\s+|pnpm\s+exec\s+|yarn\s+)?(jest|vitest|mocha)\b|pytest\b|python3?\s+-m\s+(pytest|unittest)\b|python3?\s+(\S*/)?test[^\s;&|]*\.py\b|go\s+test\b|cargo\s+(test|nextest)\b|(gradle|gradlew|\./gradlew)\b[^;&|\n]*\btest\b|mvn\b[^;&|\n]*\b(test|verify)\b|make\s+(test|check)\b|(bash|sh|zsh)\s+(\S*/)?test[^\s;&|]*\.sh\b|\./(\S*/)?test[^\s;&|]*\.sh\b|deno\s+test\b)"#

    nonisolated(unsafe) static let regex: Regex<AnyRegexOutput> = {
        // 패턴은 상수라 실패하지 않는다(테스트가 확인).
        // swiftlint:disable:next force_try
        try! Regex(pattern).wordBoundaryKind(.simple)
    }()

    /// 저장하는 명령 길이(문자).
    public static let commandLimit = 300

    /// outbox 필터와 같은 판정: 명령 어딘가에 검증 명령 꼴이 있는지(따옴표 안도 본다 — 넓게 남긴다).
    public static func matchesPattern(_ command: String) -> Bool {
        command.firstMatch(of: regex) != nil
    }

    /// 명령을 나눈 조각과 조각 사이 연결자.
    public struct Parsed: Equatable, Sendable {
        public let segments: [String]
        /// `connectors[i]`는 `segments[i]`와 `segments[i+1]` 사이(`&&` `||` `|` `;` `&`, 줄바꿈은 `;`).
        public let connectors: [String]
        /// 검증 명령인 조각 번호들
        public let verifying: [Int]
        /// 명령이 `&`로 끝나 뒤에서 돈다(종료 코드는 시작 결과일 뿐).
        public var background = false

        /// 명령 전체의 종료 코드가 검증 조각의 결과를 그대로 나타내는지.
        /// 첫 검증 조각 앞은 `&&`·`;`·`|`만(앞이 `||`면 검증 조각이 돌지 않았을 수 있다),
        /// 뒤는 `&&`만(`| tail`, `; echo`, `|| true`, `&`는 다른 명령의 결과가 남는다).
        public var decidesExitStatus: Bool {
            guard let first = verifying.first else { return false }
            let before = connectors.prefix(first)
            let after = connectors.dropFirst(first)
            return !background && before.allSatisfy { ["&&", ";", "|"].contains($0) } && after.allSatisfy { $0 == "&&" }
        }

        /// 검증 조각을 짝짓기용으로 다듬은 것(리다이렉션·앞 변수 대입 제거, 공백 하나로).
        public var keys: [String] { verifying.map { VerificationCommand.normalize(segments[$0]) } }
    }

    /// 따옴표를 존중해 명령을 나누고 검증 조각을 찾는다. 검증 조각이 없으면 nil(따옴표 안에만 있으면 nil).
    public static func parse(_ command: String) -> Parsed? {
        let (segments, connectors, background) = split(command)
        // 따옴표 안 글은 명령이 아니다(`git commit -m "fix; swift test"`)
        let verifying = segments.indices.filter { maskingQuotes(segments[$0]).firstMatch(of: regex) != nil }
        guard !verifying.isEmpty else { return nil }
        var parsed = Parsed(segments: segments, connectors: connectors, verifying: verifying)
        parsed.background = background
        return parsed
    }

    /// 종료 코드로 결과를 정한다. 코드를 모르거나 명령 전체의 결과가 검증 조각의 것이 아니면 `unknown`.
    public static func outcome(_ parsed: Parsed, exitCode: Int?) -> CheckOutcome {
        guard let exitCode, parsed.decidesExitStatus else { return .unknown }
        return exitCode == 0 ? .pass : .fail
    }

    /// 화면·저장용 명령: 앞뒤 공백 정리, 변수 대입 값 가림(`TOKEN=…`), 300자까지.
    public static func display(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let masked = trimmed.replacing(/(^|[\s;&|(])([A-Za-z_][A-Za-z0-9_]*)=("[^"]*"|'[^']*'|[^\s;&|]*)/) { match in
            "\(match.output.1)\(match.output.2)=…"
        }
        return masked.count > commandLimit ? String(masked.prefix(commandLimit - 1)) + "…" : masked
    }

    /// 짝짓기용 조각: 리다이렉션(`2>&1`, `> out.txt`)·앞 변수 대입·괄호를 빼고 공백을 하나로.
    public static func normalize(_ segment: String) -> String {
        // `2>&1`·`>&2`는 그것만, `> out.txt`·`2>/dev/null`은 파일 이름까지
        var text = segment.replacing(/&?[0-9]*[<>]+&[0-9-]+|&?[0-9]*[<>]+\s*[^\s&|;<>]+/, with: " ")
        text = text.replacing(/^\s*([A-Za-z_][A-Za-z0-9_]*=\S*\s+)+/, with: "")
        text = text.replacing(/[()]/, with: " ")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 따옴표(`'` `"`)와 역슬래시를 존중해 `&&` `||` `|` `;` `&` 줄바꿈에서 나눈다.
    /// `2>&1`·`&>` 같은 리다이렉션의 `&`는 나누지 않는다.
    /// 따옴표로 감싼 글을 `_`로 바꾼다(길이·따옴표는 그대로).
    static func maskingQuotes(_ text: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false
        for c in text {
            if escaped { result.append(quote == nil ? c : "_"); escaped = false; continue }
            if c == "\\" && quote != "'" { result.append(c); escaped = true; continue }
            if let q = quote {
                if c == q { quote = nil; result.append(c) } else { result.append("_") }
                continue
            }
            if c == "'" || c == "\"" { quote = c }
            result.append(c)
        }
        return result
    }

    static func split(_ command: String) -> (segments: [String], connectors: [String], background: Bool) {
        var segments: [String] = []
        var connectors: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        let chars = Array(command)
        var i = 0
        func close(_ connector: String) {
            segments.append(current.trimmingCharacters(in: .whitespaces))
            connectors.append(connector)
            current = ""
        }
        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if escaped { current.append(c); escaped = false; i += 1; continue }
            if c == "\\" && quote != "'" { current.append(c); escaped = true; i += 1; continue }
            if let q = quote {
                if c == q { quote = nil }
                current.append(c); i += 1; continue
            }
            switch c {
            case "'", "\"":
                quote = c; current.append(c)
            case "&":
                let previous = current.last
                if next == "&" { close("&&"); i += 1 }
                else if previous == ">" || previous == "<" || next == ">" { current.append(c) }
                else { close("&") }
            case "|":
                if next == "|" { close("||"); i += 1 } else if next == "&" { close("|"); i += 1 } else { close("|") }
            case ";", "\n":
                close(";")
            default:
                current.append(c)
            }
            i += 1
        }
        segments.append(current.trimmingCharacters(in: .whitespaces))
        // 끝이 `&`(빈 조각 앞)이면 뒤에서 도는 명령
        let background = segments.last?.isEmpty == true && connectors.last == "&"
        // 빈 조각(끝의 `;`, 빈 줄)은 연결자와 함께 뺀다
        var keptSegments: [String] = []
        var keptConnectors: [String] = []
        for (index, segment) in segments.enumerated() {
            if segment.isEmpty { continue }
            if !keptSegments.isEmpty { keptConnectors.append(connectors[index - 1]) }
            keptSegments.append(segment)
        }
        return (keptSegments, keptConnectors, background)
    }
}

/// 검증 근거의 결과. 훅은 pass·fail·unknown, 에이전트 보고는 pass·fail·skipped.
public enum CheckOutcome: String, Codable, Sendable, CaseIterable {
    case pass, fail, skipped, unknown
}

/// 근거 출처. hook = 훅이 본 명령 실행(화면 「확인됨」), agent = 에이전트 보고(화면 「보고」).
public enum CheckSource: String, Codable, Sendable, CaseIterable {
    case hook, agent
}
