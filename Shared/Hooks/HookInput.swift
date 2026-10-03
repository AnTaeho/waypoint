import Foundation

/// Claude Code·Codex 훅 입력(JSON)에서 Waypoint가 쓰는 필드를 정규화한다.
/// 필드 이름은 SPEC 5장(Claude 실측 + Codex 공식 훅 문서). 모르는 필드는 무시한다.
public struct HookInput {
    public let provider: AgentProvider
    public let event: String
    public let sessionID: String
    /// 훅의 시작 폴더. 원격 세션을 로컬 작업 트리에 이으면(`linkRemote`) 로컬 경로로 옮긴 값이다.
    public internal(set) var cwd: String
    /// 원격 모드 훅 스크립트가 붙인 git 작업 트리(`waypoint_remote`, TRK-53). 로컬 훅이면 nil.
    public let remote: RemoteCheckout?
    /// 원격 작업 트리를 이은 로컬 작업 트리. 처리기가 정한다(`HookProcessor.linkRemote`). 잇지 않았으면 nil.
    public internal(set) var linkedCheckout: String?
    /// 이었을 때 원래(원격 쪽) 시작 폴더. 세션 `cwd`에는 이 값을 적는다(화면에 보이는 폴더).
    public internal(set) var remoteCwd: String?
    /// 서브에이전트 안에서 난 훅이면 서브에이전트 실행 ID
    public let agentID: String?
    public let agentType: String?
    /// SessionStart: startup/resume/clear/compact/fork
    public let source: String?
    /// SessionEnd: 끝난 이유
    public let reason: String?
    /// UserPromptSubmit: 사용자 문장. 실측·문서는 `prompt`, 옛 문서 예시의 `prompt_text`도 받는다.
    public let prompt: String?
    /// 요청 한 건의 ID. Claude는 `prompt_id`(2.1.196+), Codex는 `turn_id`. 재수신 중복 판정에 쓴다.
    public let promptID: String?
    public let toolName: String?
    public let toolUseID: String?
    public let toolInput: [String: Any]
    public let toolResponse: [String: Any]
    /// PostToolUseFailure: 실패 설명. Bash는 첫 줄이 `Exit code N`(문서·2.1.286 실측).
    public let error: String?
    /// PostToolUseFailure: 도구가 중단돼 실패했는지.
    public let isInterrupt: Bool
    /// 훅을 부른 Claude Code 프로세스 PID. 본문 JSON이 아니라 HTTP 머리 `X-Waypoint-Claude-PID`나
    /// outbox 줄의 `claudePid`에서 온다. 없으면 nil.
    public var claudePid: Int?
    public var processPid: Int?

    /// 본문을 읽는다. JSON 객체가 아니거나 `session_id`가 없으면 nil.
    /// `event`는 경로(`/hooks/<EventName>`)나 outbox의 이름을 우선하고, 없으면 `hook_event_name`.
    public init?(event: String?, json: Data, provider: AgentProvider = .claude) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        self.init(event: event, object: object, provider: provider)
    }

    public init?(event: String?, object: [String: Any], provider: AgentProvider = .claude) {
        func string(_ key: String) -> String? {
            guard let value = object[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        guard let sessionID = string("session_id"),
              let event = event ?? string("hook_event_name")
        else { return nil }
        self.event = event
        self.provider = provider
        self.sessionID = provider.sessionID(sessionID)
        self.cwd = string("cwd") ?? ""
        self.remote = RemoteCheckout(object["waypoint_remote"])
        self.agentID = string("agent_id").map { provider.sessionID($0) }
        self.agentType = object["agent_type"] as? String
        self.source = string("source")
        self.reason = string("reason")
        self.prompt = string("prompt") ?? string("prompt_text")
        self.promptID = string("prompt_id") ?? string("turn_id")
        self.toolName = string("tool_name")
        self.toolUseID = string("tool_use_id")
        self.error = string("error")
        self.isInterrupt = object["is_interrupt"] as? Bool ?? false
        if provider == .codex {
            self.toolInput = CodexHookAdapter.toolInput(object["tool_input"])
            self.toolResponse = CodexHookAdapter.toolResponse(object["tool_response"])
        } else {
            self.toolInput = object["tool_input"] as? [String: Any] ?? [:]
            self.toolResponse = object["tool_response"] as? [String: Any] ?? [:]
        }
    }

    /// 원격 작업 트리에 이었으면 그 아래 경로를 로컬 경로로 옮긴다. 아니면 그대로.
    public func localPath(_ path: String) -> String {
        guard let remote, let linkedCheckout else { return path }
        return RemoteMatcher.map(path, from: remote.root, to: linkedCheckout)
    }

    /// 세션에 적을 시작 폴더(이었으면 원격 쪽 원래 폴더)
    public var sessionCwd: String { remoteCwd ?? cwd }
}

/// 훅 입력에서 뽑는 사실들. 순수 함수라 픽스처로 바로 테스트한다.
public enum HookParsing {

    /// PID 문자열·숫자를 검사한다. 1보다 큰 정수만(0·1·음수·숫자 아닌 것은 nil).
    public static func pid(_ raw: Any?) -> Int? {
        let value: Int?
        switch raw {
        case let string as String: value = Int(string.trimmingCharacters(in: .whitespaces))
        case let number as NSNumber:
            value = CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : Int(exactly: number.doubleValue)
        default: value = nil
        }
        guard let value, value > 1, value <= Int(Int32.max) else { return nil }
        return value
    }

    /// `Session.lastPrompt`에 넣는 최대 길이(문자 단위).
    public static let lastPromptLimit = 300

    /// UserPromptSubmit에서 `Session.lastPrompt`로 남길 사용자 문장. 앞뒤 공백을 정리하고 300자까지.
    /// nil: 서브에이전트 훅(`agent_id` 있음), 문장이 없거나 빈 경우, `<`로 시작하는 자동 메시지
    /// (서브에이전트 완료 알림 `<agent-message from=…>`, `<task-notification>` 등 — 2.1.283 실측).
    /// 사용자가 붙여 넣은 글(`<pasted_content id=…>…</pasted_content>`)은 태그만 벗겨 남긴다. 슬래시 명령은 그대로.
    public static func userPrompt(_ input: HookInput) -> String? {
        guard input.agentID == nil, let raw = input.prompt else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<pasted_content") {
            text = text.replacing(/<\/?pasted_content[^>]*>/, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty, !text.hasPrefix("<") else { return nil }
        return String(text.prefix(lastPromptLimit))
    }

    /// 서브에이전트를 띄우는 도구 이름(현재 `Agent`, 옛 이름 `Task`).
    public static let subagentTools: Set<String> = ["Agent", "Task"]

    /// 텍스트 안의 `[LDG-16]` 꼴 카드 ID. 대괄호로 감싼 것만, 나온 순서대로.
    public static func cardReferences(in text: String) -> [(key: String, number: Int)] {
        let pattern = /\[([A-Z]{2,5})-([0-9]{1,6})\]/
        return text.matches(of: pattern).compactMap { match in
            guard let number = Int(match.output.2) else { return nil }
            return (key: String(match.output.1), number: number)
        }
    }

    /// 문자열의 줄 수. 빈 문자열은 0, 끝 줄바꿈은 줄로 세지 않는다.
    public static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let count = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return text.hasSuffix("\n") ? count - 1 : count
    }

    /// PostToolUse에서 바뀐 파일(절대 경로)과 줄 수.
    /// 실제 `tool_response`의 diff 조각(`structuredPatch`, `bashEditDiff.files[].hunks`)이 있으면
    /// 그 `+`/`-` 줄을 센다(2.1.283 실측). 없으면 입력으로 추정한다.
    /// - Edit: old_string/new_string 줄 수, MultiEdit: edits 합, Write: content 줄 수(지운 줄 0)
    /// - Bash: `bashEditDiff.changedFiles`(조각이 없는 파일은 줄 수 0)
    public static func changedFiles(_ input: HookInput) -> [(path: String, added: Int, removed: Int)] {
        if input.provider == .codex, input.toolName == "apply_patch" {
            return CodexHookAdapter.changedFiles(input)
        }
        let tool = input.toolInput
        let patch = input.toolResponse["structuredPatch"] as? [[String: Any]] ?? []
        switch input.toolName {
        case "Edit":
            guard let path = tool["file_path"] as? String else { return [] }
            if let counted = hunkLines(patch) { return [(path, counted.added, counted.removed)] }
            return [(path, lineCount(tool["new_string"] as? String ?? ""), lineCount(tool["old_string"] as? String ?? ""))]
        case "MultiEdit":
            guard let path = tool["file_path"] as? String else { return [] }
            if let counted = hunkLines(patch) { return [(path, counted.added, counted.removed)] }
            let edits = tool["edits"] as? [[String: Any]] ?? []
            let added = edits.reduce(0) { $0 + lineCount($1["new_string"] as? String ?? "") }
            let removed = edits.reduce(0) { $0 + lineCount($1["old_string"] as? String ?? "") }
            return [(path, added, removed)]
        case "Write":
            guard let path = tool["file_path"] as? String else { return [] }
            // 새 파일(`type: create`)은 structuredPatch가 비어 있다 → content 줄 수
            if let counted = hunkLines(patch) { return [(path, counted.added, counted.removed)] }
            return [(path, lineCount(tool["content"] as? String ?? ""), 0)]
        case "Bash":
            let diff = input.toolResponse["bashEditDiff"] as? [String: Any]
            var result: [(path: String, added: Int, removed: Int)] = []
            for file in diff?["files"] as? [[String: Any]] ?? [] {
                guard let path = file["filePath"] as? String else { continue }
                let counted = hunkLines(file["hunks"] as? [[String: Any]] ?? [])
                result.append((path, counted?.added ?? 0, counted?.removed ?? 0))
            }
            // files는 잘릴 수 있다(`moreFiles`). 목록에만 있는 파일은 줄 수 0으로
            for path in diff?["changedFiles"] as? [String] ?? [] where !result.contains(where: { $0.path == path }) {
                result.append((path, 0, 0))
            }
            return result
        default:
            return []
        }
    }

    /// diff 조각들의 `lines`에서 `+`로 시작하는 줄과 `-`로 시작하는 줄 수. 조각이 없으면 nil.
    public static func hunkLines(_ hunks: [[String: Any]]) -> (added: Int, removed: Int)? {
        guard !hunks.isEmpty else { return nil }
        var added = 0, removed = 0
        for hunk in hunks {
            for line in hunk["lines"] as? [String] ?? [] {
                if line.hasPrefix("+") { added += 1 } else if line.hasPrefix("-") { removed += 1 }
            }
        }
        return (added, removed)
    }

    /// 커밋 (브랜치, 해시, 메시지).
    /// 1) `tool_response.gitOperation.commit`(`sha`, `branch`, `kind`, 2.1.283 실측)이 있으면 그것을 쓰고
    ///    메시지는 출력 첫 줄 `[브랜치 해시] 메시지`에서 찾는다(없으면 빈 문자열).
    /// 2) 없으면 명령에 `git commit`이 있고 출력이 그 꼴일 때만. 아니면 nil.
    public static func commit(_ input: HookInput) -> (branch: String?, hash: String, message: String)? {
        guard input.toolName == "Bash" else { return nil }
        let stdout = input.toolResponse["stdout"] as? String ?? ""
        let parsed = commitLine(in: stdout)
        if let operation = input.toolResponse["gitOperation"] as? [String: Any],
           let commit = operation["commit"] as? [String: Any],
           let sha = commit["sha"] as? String, !sha.isEmpty {
            let branch = (commit["branch"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let message = parsed.flatMap { sha.hasPrefix($0.hash) || $0.hash.hasPrefix(sha) ? $0.message : nil } ?? ""
            return (branch ?? parsed?.branch, sha, message)
        }
        guard let command = input.toolInput["command"] as? String,
              command.contains("git commit") || command.contains("git -c") && command.contains(" commit")
        else { return nil }
        return parsed
    }

    /// 출력에서 `[브랜치 해시] 메시지` 줄을 찾는다.
    static func commitLine(in stdout: String) -> (branch: String?, hash: String, message: String)? {
        let pattern = /^\[(.+?) (?:\(root-commit\) )?([0-9a-f]{7,40})\] (.*)$/
        for line in stdout.split(separator: "\n") {
            guard let match = String(line).wholeMatch(of: pattern) else { continue }
            let branch = String(match.output.1)
            let named = branch == "detached HEAD" ? nil : branch
            return (named, String(match.output.2), String(match.output.3))
        }
        return nil
    }
}
