import Foundation

/// 훅이 본 검증 명령 실행(SPEC 5장 「검증 근거」).
extension HookParsing {

    /// 셸 명령 도구 이름. Claude `Bash`, Codex는 문서상 `Bash`(unified exec 포함), 옛 이름도 받는다.
    public static let shellTools: Set<String> = ["Bash", "shell", "exec_command", "local_shell"]

    /// 훅이 본 검증 명령과 결과. 셸 도구가 아니거나 검증 명령이 아니면 nil.
    /// - Claude `PostToolUse`: 0으로 끝난 명령(비영 종료는 `PostToolUseFailure`로 온다). 단 `interrupted`,
    ///   백그라운드 실행(`backgroundTaskId`·`run_in_background` — 실행 결과가 아니라 시작만 알린다)은 결과 모름.
    /// - Claude `PostToolUseFailure`: `error` 첫 줄 `Exit code N`. `is_interrupt`거나 그 줄이 없으면 결과 모름.
    /// - Codex `PostToolUse`(비영 종료도 이것): `metadata.exit_code`·`exit_code`, 없으면 출력의
    ///   `Process exited with code N`·`Exit code: N` 줄. 모르면 결과 모름.
    /// 명령 전체의 종료 코드가 검증 조각의 것이 아니면(`| tail`, `; echo` 등) 결과 모름(`VerificationCommand.outcome`).
    public static func check(_ input: HookInput) -> (command: String, outcome: CheckOutcome, exitCode: Int?)? {
        guard input.event == "PostToolUse" || input.event == "PostToolUseFailure",
              let tool = input.toolName, shellTools.contains(tool),
              let command = shellCommand(input.toolInput),
              let parsed = VerificationCommand.parse(command)
        else { return nil }
        let exitCode = exitCode(input)
        let outcome = exitCode == nil ? CheckOutcome.unknown : VerificationCommand.outcome(parsed, exitCode: exitCode)
        return (VerificationCommand.display(command), outcome, exitCode)
    }

    /// `tool_input.command`. Codex는 배열(`["bash", "-lc", "…"]`)일 수 있어 셸 인자를 꺼낸다.
    static func shellCommand(_ toolInput: [String: Any]) -> String? {
        if let text = toolInput["command"] as? String { return text }
        guard let parts = toolInput["command"] as? [String], !parts.isEmpty else { return nil }
        if parts.count >= 3, ["bash", "sh", "zsh"].contains((parts[0] as NSString).lastPathComponent),
           parts[1].hasPrefix("-"), parts[1].contains("c") {
            return parts[2]
        }
        return parts.joined(separator: " ")
    }

    /// 결과를 정할 종료 코드. 모르면 nil.
    static func exitCode(_ input: HookInput) -> Int? {
        let response = input.toolResponse
        if input.event == "PostToolUseFailure" {
            guard !input.isInterrupt, let error = input.error,
                  let first = error.split(separator: "\n", omittingEmptySubsequences: false).first,
                  let match = String(first).wholeMatch(of: /Exit code (-?[0-9]+)/)
            else { return nil }
            return Int(match.output.1)
        }
        if input.provider == .codex {
            if let metadata = response["metadata"] as? [String: Any], let code = integer(metadata["exit_code"]) { return code }
            if let code = integer(response["exit_code"]) { return code }
            let output = response["stdout"] as? String ?? ""
            for line in output.split(separator: "\n") {
                if let m = String(line).wholeMatch(of: /(?:Process exited with code|Exit code:) (-?[0-9]+)/) {
                    return Int(m.output.1)
                }
            }
            return nil
        }
        // Claude PostToolUse: 성공한 호출만 온다.
        if response["interrupted"] as? Bool == true { return nil }
        if response["backgroundTaskId"] != nil || input.toolInput["run_in_background"] as? Bool == true { return nil }
        return integer(response["exitCode"]) ?? 0
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): Int(exactly: number.doubleValue)
        case let text as String: Int(text)
        default: nil
        }
    }
}
