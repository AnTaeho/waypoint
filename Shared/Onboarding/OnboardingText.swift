import Foundation

/// 온보딩 화면 문구. 설치기 결과·오류를 사용자 말로 옮긴다(파일은 `~` 경로로, 만든 쪽 용어는 빼고).
public enum OnboardingText {

    /// 계획의 파일 한 줄: 「~/.claude/settings.json · 바꿈」
    public static func change(_ change: IntegrationPlan.FileChange, home: String) -> String {
        "\(GuideFormat.displayPath(change.path, home: home)) · \(verb(change))"
    }

    public static func verb(_ change: IntegrationPlan.FileChange) -> String {
        switch (change.before, change.after) {
        case (nil, _): "새로 만듦"
        case (_, nil): "지움"
        case let (before, after) where before == after: "권한만 바꿈"
        default: "바꿈"
        }
    }

    public static func command(_ command: IntegrationPlan.Command) -> String {
        switch command {
        case .claudeMCPAdd: "Claude Code에 Waypoint 등록"
        case .claudeMCPRemove: "Claude Code에서 Waypoint 등록 지움"
        }
    }

    /// 건너뛴 단계: 「상태줄 건너뜀 · 명령 상태줄이 아님」
    public static func note(_ note: IntegrationPlan.Note) -> String {
        let step: String
        switch note.step {
        case "MCP 등록", "MCP 해제": step = "Waypoint 등록"
        case "tracker 스킬": step = "/tracker"
        default: step = note.step
        }
        let reason = note.reason.replacingOccurrences(of: "waypoint MCP 서버가", with: "waypoint 등록이")
        return "\(step) 건너뜀 · \(reason)"
    }

    /// 설치기를 멈춘 오류의 원인 문장
    public static func error(_ error: IntegrationInstallError, home: String) -> String {
        func file(_ path: String) -> String { GuideFormat.displayPath(path, home: home) }
        switch error {
        case .unreadable(let path, let reason):
            return "\(file(path))을 읽을 수 없음 · \(reason)"
        case .conflict(let reason):
            return "직접 고친 설정과 겹침 · \(reason)"
        case .missingResource(let name):
            return "앱 안의 연결 파일 \(name)을 찾지 못함"
        case .changedSincePlan(let path):
            return "확인하는 사이 \(file(path))이 바뀜"
        case .backupFailed(let reason):
            return "백업을 남기지 못해 아무것도 바꾸지 않음 · \(reason)"
        case .writeFailed(let path, let reason, let rolledBack, let failures):
            let tail = rolledBack ? "원래대로 되돌림" : "되돌리지 못한 파일 \(failures.count)개"
            return "\(file(path))에 쓰지 못함 · \(reason) · \(tail)"
        }
    }

    /// 다른 오류(컨텍스트를 만들지 못함 등)
    public static func error(_ error: Error, home: String) -> String {
        if let error = error as? IntegrationInstallError { return Self.error(error, home: home) }
        return error.localizedDescription
    }

    /// 끝나지 않은 명령 단계. 됐으면 nil
    public static func outcome(_ outcome: IntegrationInstaller.StepOutcome, command: IntegrationPlan.Command) -> String? {
        switch outcome {
        case .done: nil
        case .executableMissing: "\(Self.command(command)) 못 함 · claude 실행 파일을 찾지 못함"
        case .failed(let reason): "\(Self.command(command)) 실패 · \(reason)"
        }
    }

    /// 결과에서 안 된 것들(부분 실패)
    public static func failures(_ result: IntegrationInstaller.Result) -> [String] {
        zip(result.plan.commands, result.commandOutcomes).compactMap { outcome($1, command: $0) }
    }

    /// 연결한 뒤 도구 쪽에서 할 일 한 줄
    public static func trust(_ provider: AgentProvider) -> String {
        switch provider {
        case .claude: "Claude Code는 새로 연 세션부터 기록됨"
        case .codex: "새로 연 Codex에서 /hooks를 열어 Waypoint를 신뢰"
        }
    }

    #if os(macOS)
    /// 기록을 받을 수 없는 까닭. 받을 수 있으면 nil
    public static func serverProblem(_ state: LocalServer.State) -> String? {
        switch state {
        case .ready: nil
        case .stopped, .starting: "기록 받을 준비 중"
        case .failed(let reason): "기록을 받지 못하는 중 · \(reason)"
        }
    }
    #endif

    public static func blocker(_ blocker: OnboardingProgress.Blocker) -> String? {
        switch blocker {
        case .noToolSelected, .noProject, .waiting, .notInstalled: nil
        case .installBlocked(let reason): reason
        case .attention(let provider, let detail): "\(provider.name) · \(detail)"
        case .pendingRegistration: "등록 창에서 확인을 기다리는 중"
        case .archivedProject(let key): "\(key)는 보관된 프로젝트 · 보관을 풀면 기록됨"
        case .serverDown(let reason): reason
        case .unlinked(let provider): "\(provider.name) 기록이 왔지만 등록된 폴더 밖"
        }
    }
}
