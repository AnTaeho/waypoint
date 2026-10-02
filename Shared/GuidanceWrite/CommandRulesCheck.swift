import Foundation

/// Codex 명령 규칙(`*.rules`) 저장 전 검사. Codex 실행 파일이 있으면 Codex에게 새 내용을 읽혀 보고
/// (`codex execpolicy check --rules <임시 파일> -- <없는 명령>`), 없거나 시간 안에 끝나지 않으면 자체 검사로 대신한다.
public enum CommandRulesCheck {

    public enum Method: String, Sendable, Equatable {
        /// Codex가 파일을 읽어 봤다
        case codex
        /// 괄호·따옴표·함수 이름만 본 자체 검사
        case builtIn
    }

    public struct Outcome: Equatable, Sendable {
        public var method: Method
        /// 문제. nil이면 저장해도 된다.
        public var problem: String?
        /// 문제 줄(1부터). 모르면 nil.
        public var line: Int?

        public init(method: Method, problem: String? = nil, line: Int? = nil) {
            self.method = method
            self.problem = problem
            self.line = line
        }

        public var isValid: Bool { problem == nil }

        /// 화면용 한 줄: 「줄 2 · invalid decision: maybe」
        public var message: String? {
            guard let problem else { return nil }
            return line.map { "줄 \($0) · \(problem)" } ?? problem
        }
    }

    /// Codex 규칙 파일에서 부를 수 있는 함수(codex-cli 0.159에서 확인)
    public static let knownFunctions: Set<String> = ["prefix_rule", "host_executable", "network_rule"]
    /// Codex 검사 시간 상한(초)
    public static let timeout: TimeInterval = 3

    /// Codex가 있으면 Codex로, 없거나 시간이 넘으면 자체 검사로.
    public static func check(_ content: String, codex: String?) -> Outcome {
        #if os(macOS)
        if let codex, let outcome = run(codex: codex, content: content) { return outcome }
        #endif
        return builtIn(content)
    }

    // MARK: - 자체 검사

    /// 규칙마다: 괄호 짝, 한 줄 문자열이 그 줄에서 닫힘, `알려진 함수(…)` 꼴. 빈 파일·주석만 있는 파일은 통과.
    public static func builtIn(_ content: String) -> Outcome {
        let document = GuidanceDocument.parse(content, format: .commandRules)
        if let reason = document.ambiguity {
            return Outcome(method: .builtIn, problem: reason, line: firstBrokenLine(content))
        }
        for item in document.items {
            if let offset = unclosedQuoteLine(item.text) {
                return Outcome(method: .builtIn, problem: "닫히지 않은 따옴표", line: item.lines.lowerBound + offset + 1)
            }
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(text.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            let afterName = text.dropFirst(name.count).drop { $0 == " " || $0 == "\t" }
            guard afterName.hasPrefix("(") else {
                return Outcome(method: .builtIn, problem: "함수 호출 꼴이 아님", line: item.lines.lowerBound + 1)
            }
            guard knownFunctions.contains(name) else {
                return Outcome(method: .builtIn, problem: "모르는 이름 \(name)", line: item.lines.lowerBound + 1)
            }
            guard closesAtEnd(item.text) else {
                return Outcome(method: .builtIn, problem: "규칙 뒤에 글이 더 있음", line: item.lines.upperBound)
            }
        }
        return Outcome(method: .builtIn)
    }

    /// 괄호가 처음 어긋나는(또는 끝까지 닫히지 않은 규칙이 시작하는) 줄.
    static func firstBrokenLine(_ content: String) -> Int? {
        let lines = content.components(separatedBy: "\n")
        var scanner = GuidanceRulesSplitter.Scanner()
        var start: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if start == nil {
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                start = index
            }
            scanner.feed(line)
            if scanner.broken { return index + 1 }
            if scanner.isBalanced { start = nil }
        }
        return start.map { $0 + 1 }
    }

    /// 한 줄 문자열(`"…"`·`'…'`)이 그 줄 안에서 닫히지 않은 줄(규칙 안 0부터). 여러 줄 문자열은 넘긴다.
    static func unclosedQuoteLine(_ text: String) -> Int? {
        var triple: String?
        for (offset, line) in text.components(separatedBy: "\n").enumerated() {
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
                if c == "#" { break }
                if c == "\"" || c == "'" {
                    let three = String(repeating: String(c), count: 3)
                    if String(chars[i..<min(i + 3, chars.count)]) == three {
                        triple = three
                        i += 3
                        continue
                    }
                    quote = c
                }
                i += 1
            }
            if quote != nil { return offset }
        }
        return nil
    }

    /// 첫 괄호가 닫힌 뒤에는 공백·주석만.
    static func closesAtEnd(_ text: String) -> Bool {
        var scanner = GuidanceRulesSplitter.Scanner()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let chars = Array(line)
            // 줄을 앞에서부터 늘려 가며 깊이가 0으로 돌아오는 첫 자리를 찾는다
            for end in chars.indices where chars[end] == ")" || chars[end] == "]" || chars[end] == "}" {
                var probe = scanner
                probe.feed(String(chars[...end]))
                guard probe.isBalanced, !probe.broken else { continue }
                let rest = String(chars[(end + 1)...]).trimmingCharacters(in: .whitespaces)
                let after = lines.dropFirst(index + 1).allSatisfy {
                    let t = $0.trimmingCharacters(in: .whitespaces)
                    return t.isEmpty || t.hasPrefix("#")
                }
                return (rest.isEmpty || rest.hasPrefix("#")) && after
            }
            scanner.feed(line)
        }
        return false
    }

    // MARK: - Codex

    #if os(macOS)
    /// 앱 PATH가 짧으므로 재개 열기(TRK-12)와 같은 폴더들에서 `codex`를 찾는다.
    public static func findCodex(home: String = NSHomeDirectory(),
                                 path: String? = ProcessInfo.processInfo.environment["PATH"]) -> String? {
        ToolLaunch.executable(provider: .codex, home: home, path: path) {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// 새 내용을 0700 임시 폴더에 쓰고 Codex에게 읽힌다. `CODEX_HOME`도 그 임시 폴더로 돌려 사용자 Codex 홈에 아무것도 남기지 않는다.
    /// 실행하지 못했거나 시간이 넘으면 nil.
    static func run(codex: String, content: String, timeout: TimeInterval = timeout) -> Outcome? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("waypoint-rules-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let home = dir.appendingPathComponent("codex-home", isDirectory: true)
        let file = dir.appendingPathComponent("check.rules")
        do {
            try fm.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try Data(content.utf8).write(to: file)
        } catch {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codex)
        // 규칙에 걸리지 않을 없는 명령으로 검사한다(파일을 읽어 들이는지만 본다).
        process.arguments = ["execpolicy", "check", "--rules", file.path, "--", "waypoint-check-\(UUID().uuidString.prefix(8))"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        process.environment = environment
        process.currentDirectoryURL = dir
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 1)
            return nil
        }
        let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus == 0 && !stderr.contains("failed to parse policy") {
            return Outcome(method: .codex)
        }
        let parsed = parseError(stderr, fileName: file.lastPathComponent)
        return Outcome(method: .codex, problem: parsed.message, line: parsed.line)
    }
    #endif

    /// Codex 오류 출력에서 마지막 `error:` 문장과, 그 줄 원문이 함께 찍힌 경우에만 줄 번호.
    /// (구문 오류는 줄 번호가 1:1로 찍히고 원문이 비어 있는 경우가 있어 믿지 않는다.)
    public static func parseError(_ stderr: String, fileName: String) -> (message: String, line: Int?) {
        let lines = stderr.components(separatedBy: "\n")
        var message: String?
        var line: Int?
        for (index, raw) in lines.enumerated() {
            var trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("starlark error: ") { trimmed = String(trimmed.dropFirst("starlark error: ".count)) }
            if trimmed.hasPrefix("error: ") {
                message = String(trimmed.dropFirst("error: ".count)).trimmingCharacters(in: .whitespaces)
                line = nil
            } else if trimmed.hasPrefix("--> "), let range = trimmed.range(of: "\(fileName):", options: .backwards) {
                // 경로는 절대 경로로 찍힌다: `--> /…/check.rules:2:1`
                let parts = trimmed[range.upperBound...].split(separator: ":")
                if let number = parts.first.flatMap({ Int($0) }),
                   lines.dropFirst(index + 1).prefix(3).contains(where: {
                       $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(number) |")
                   }) {
                    line = number
                }
            }
        }
        let fallback = lines.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "읽지 못함"
        return (message ?? fallback, line)
    }
}
