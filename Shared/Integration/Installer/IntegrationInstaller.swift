import Foundation

/// 설치할 파일의 원본. 앱은 번들 리소스(`project.yml`이 저장소 `integration/`의 파일을 빌드 때 복사), 테스트는 저장소 경로.
public struct IntegrationSources: Equatable, Sendable {
    public var hookScript: URL
    public var statusLineTap: URL
    public var codexBridge: URL
    public var trackerSkill: URL

    public init(hookScript: URL, statusLineTap: URL, codexBridge: URL, trackerSkill: URL) {
        self.hookScript = hookScript
        self.statusLineTap = statusLineTap
        self.codexBridge = codexBridge
        self.trackerSkill = trackerSkill
    }

    /// 저장소 뿌리 아래의 원본
    public static func repository(root: URL) -> IntegrationSources {
        IntegrationSources(
            hookScript: root.appendingPathComponent("integration/hooks/waypoint-hook.sh"),
            statusLineTap: root.appendingPathComponent("integration/statusline/waypoint-statusline-tap.sh"),
            codexBridge: root.appendingPathComponent("integration/codex/waypoint-codex-hook.sh"),
            trackerSkill: root.appendingPathComponent("integration/skills/tracker/SKILL.md"))
    }

    /// 앱 번들 리소스. 하나라도 없으면 nil.
    public static func bundle(_ bundle: Bundle = .main) -> IntegrationSources? {
        guard let hook = bundle.url(forResource: "waypoint-hook", withExtension: "sh"),
              let tap = bundle.url(forResource: "waypoint-statusline-tap", withExtension: "sh"),
              let bridge = bundle.url(forResource: "waypoint-codex-hook", withExtension: "sh"),
              let skill = bundle.url(forResource: "SKILL", withExtension: "md") else { return nil }
        return IntegrationSources(hookScript: hook, statusLineTap: tap, codexBridge: bridge, trackerSkill: skill)
    }

    func text(_ url: URL) throws -> String {
        guard let data = FileManager.default.contents(atPath: url.path), let text = String(data: data, encoding: .utf8) else {
            throw IntegrationInstallError.missingResource(url.lastPathComponent)
        }
        return text
    }
}

/// 설치기 입력.
public struct IntegrationInstallContext: Sendable {
    /// 설정 파일이 있는 홈(테스트는 임시 폴더)
    public var home: URL
    /// 훅 명령에 적는 홈 경로. 보통 `home`과 같다(실제 설치를 임시 홈에 복사해 볼 때만 다르다).
    public var commandHome: String
    /// 평소용(47821)·Dev(47822)
    public var instance: AppInstance
    public var sources: IntegrationSources
    /// 백업을 남길 곳(`<저장 폴더>/integration-backups`)
    public var backupRoot: URL
    public var now: Date

    public init(home: URL, commandHome: String? = nil, instance: AppInstance, sources: IntegrationSources,
                backupRoot: URL, now: Date = Date()) {
        let real = IntegrationFile.resolved(home.path)
        self.home = URL(fileURLWithPath: real, isDirectory: true)
        self.commandHome = commandHome ?? real
        self.instance = instance
        self.sources = sources
        self.backupRoot = backupRoot
        self.now = now
    }

    public static let backupFolderName = "integration-backups"

    /// 지금 사용자·이 앱 인스턴스·번들 리소스. 리소스가 없으면 nil.
    public static func current(instance: AppInstance = .current, bundle: Bundle = .main) throws -> IntegrationInstallContext? {
        guard let sources = IntegrationSources.bundle(bundle) else { return nil }
        let support = try WaypointStore.supportDirectory()
        return IntegrationInstallContext(
            home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true), instance: instance, sources: sources,
            backupRoot: support.appendingPathComponent(backupFolderName, isDirectory: true))
    }

    var port: Int { Int(instance.defaultPort) }
    var mcpURL: String { "http://127.0.0.1:\(port)/mcp" }
    func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }
}

/// 앱 안 연동 설치기. 「계획 → 적용」 두 단계다. 계획은 읽기만 하고, 적용은 백업 뒤 원자적으로 쓰고 실패하면 되돌린다.
public enum IntegrationInstaller {
    /// 단계 결과(파일 밖 단계: MCP 등록)
    public enum StepOutcome: Equatable, Sendable {
        case done
        /// 실행 파일(`claude`)을 찾지 못해 하지 못했다. 나머지는 진행했다
        case executableMissing
        case failed(String)
    }

    public struct Result: Equatable, Sendable {
        public var plan: IntegrationPlan
        /// 쓴 파일이 있으면 백업 폴더
        public var backupFolder: URL?
        public var commandOutcomes: [StepOutcome]
        /// 명령 단계가 하나라도 끝나지 않았다(파일은 적용됨)
        public var isPartial: Bool { commandOutcomes.contains { $0 != .done } }
    }

    public static func plan(_ provider: AgentProvider, _ action: IntegrationPlan.Action,
                            context: IntegrationInstallContext) throws -> IntegrationPlan {
        switch provider {
        case .claude: try ClaudeInstallPlanner(context: context).plan(action)
        case .codex: try CodexInstallPlanner(context: context).plan(action)
        }
    }

    /// 계획을 적용한다. 파일을 먼저(실패하면 되돌리고 오류), 그다음 명령을 차례로 돌린다.
    @discardableResult
    public static func apply(_ plan: IntegrationPlan, context: IntegrationInstallContext,
                             applier: IntegrationApplier = IntegrationApplier(),
                             runner: ClaudeCommandRunner? = nil) throws -> Result {
        let folder = try applier.apply(plan)
        var outcomes: [StepOutcome] = []
        if !plan.commands.isEmpty {
            let runner = runner ?? ClaudeCommandRunner.system(home: context.home.path)
            for command in plan.commands {
                outcomes.append(runner.run(command))
            }
        }
        return Result(plan: plan, backupFolder: folder, commandOutcomes: outcomes)
    }
}
