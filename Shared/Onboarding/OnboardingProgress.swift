import Foundation

/// 온보딩 단계 판정(순수). 도구 고르기 → 연결(설치) → 프로젝트 → 첫 기록 → 끝.
/// 화면이 고른 단계(`requested`)와 지금 상태를 받아 실제로 보일 단계와 그 단계에서 막힌 까닭을 낸다.
/// 앞 단계가 막혀 있으면 그 단계로 돌아간다. 첫 기록 단계에서 프로젝트에 연결된 기록을 받으면 끝 단계로 넘어간다.
public struct OnboardingProgress: Equatable, Sendable {
    public enum Step: Int, CaseIterable, Comparable, Sendable {
        case tools, install, project, receive, done
        public static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
        public var next: Step { Step(rawValue: rawValue + 1) ?? .done }
        public var previous: Step { Step(rawValue: rawValue - 1) ?? .tools }
    }

    /// 프로젝트 단계에서 고른 폴더의 상태
    public enum ProjectChoice: Equatable, Sendable {
        /// 고르지 않았다
        case none
        /// 등록된(보관 아닌) 프로젝트
        case registered(key: String)
        /// 보관된 프로젝트의 폴더. 기록을 받지 않는다
        case archived(key: String)
        /// 폴더를 골랐고 등록 창에서 확인을 기다린다
        case pending
    }

    public enum Blocker: Equatable, Sendable {
        case noToolSelected
        /// 이 앱에서는 설치할 수 없다(Dev가 실제 홈에)
        case installBlocked(String)
        case notInstalled([AgentProvider])
        /// 설치돼 있지만 확인이 필요하다(`IntegrationInstallation.detail`)
        case attention(AgentProvider, String)
        case noProject
        case pendingRegistration
        case archivedProject(String)
        /// 기록을 받을 수 없다(서버가 준비되지 않음)
        case serverDown(String)
        case waiting
        /// 기록은 왔지만 프로젝트에 연결되지 않았다(등록 밖 폴더)
        case unlinked(AgentProvider)
    }

    public struct Input: Equatable, Sendable {
        public var requested: Step
        public var selected: Set<AgentProvider>
        public var installations: [AgentProvider: IntegrationInstallation]
        public var receipts: [AgentProvider: IntegrationReceipt]
        public var startedAt: Date
        /// nil이면 기록을 받을 수 있다. 아니면 그 까닭
        public var serverProblem: String?
        /// 등록된(보관 아닌) 프로젝트 수
        public var projectCount: Int
        public var project: ProjectChoice
        /// 설치를 막는 까닭(`IntegrationHomePolicy.installBlock`)
        public var installBlock: String?

        public init(requested: Step, selected: Set<AgentProvider>, installations: [AgentProvider: IntegrationInstallation],
                    receipts: [AgentProvider: IntegrationReceipt], startedAt: Date, serverProblem: String?,
                    projectCount: Int, project: ProjectChoice, installBlock: String?) {
            self.requested = requested; self.selected = selected; self.installations = installations
            self.receipts = receipts; self.startedAt = startedAt; self.serverProblem = serverProblem
            self.projectCount = projectCount; self.project = project; self.installBlock = installBlock
        }
    }

    public let input: Input
    /// 보일 단계
    public let step: Step
    /// 그 단계에서 다음으로 못 가는 까닭. nil이면 넘어갈 수 있다
    public let blocker: Blocker?

    public init(_ input: Input) {
        self.input = input
        var step = input.requested
        for earlier in Step.allCases where earlier < input.requested && earlier < .receive {
            if Self.blocker(for: earlier, input) != nil { step = earlier; break }
        }
        if step == .receive, Self.blocker(for: .receive, input) == nil { step = .done }
        if step == .done, Self.blocker(for: .receive, input) != nil { step = .receive }
        self.step = step
        self.blocker = Self.blocker(for: step, input)
    }

    /// 순서대로 볼 도구(고른 것만)
    public var tools: [AgentProvider] { AgentProvider.allCases.filter { input.selected.contains($0) } }

    /// 온보딩을 시작한 뒤 받은, 프로젝트에 연결된 기록(고른 도구 중 가장 최근)
    public var linkedReceipt: (provider: AgentProvider, receipt: IntegrationReceipt)? {
        Self.received(input).filter { $0.receipt.project != nil }.max { $0.receipt.at < $1.receipt.at }
    }

    public static func blocker(for step: Step, _ input: Input) -> Blocker? {
        let tools = AgentProvider.allCases.filter { input.selected.contains($0) }
        switch step {
        case .tools:
            return tools.isEmpty ? .noToolSelected : nil
        case .install:
            if tools.isEmpty { return .noToolSelected }
            let state = { (provider: AgentProvider) in input.installations[provider]?.state ?? .missing }
            if let block = input.installBlock, tools.contains(where: { state($0) != .ready }) { return .installBlocked(block) }
            let missing = tools.filter { state($0) == .missing }
            if !missing.isEmpty { return .notInstalled(missing) }
            if let provider = tools.first(where: { input.installations[$0]?.state == .attention }) {
                return .attention(provider, input.installations[provider]?.detail ?? "")
            }
            return nil
        case .project:
            switch input.project {
            case .registered: return nil
            case .archived(let key): return .archivedProject(key)
            case .pending: return .pendingRegistration
            case .none: return input.projectCount > 0 ? nil : .noProject
            }
        case .receive, .done:
            if let problem = input.serverProblem { return .serverDown(problem) }
            let received = received(input)
            if received.contains(where: { $0.receipt.project != nil }) { return nil }
            if let unlinked = received.max(by: { $0.receipt.at < $1.receipt.at }) { return .unlinked(unlinked.provider) }
            return .waiting
        }
    }

    /// 시작 시각 이후 활동의 기록(고른 도구만). 늦게 재전송된 옛 기록은 활동 시각(`at`)이 앞이라 빠진다.
    static func received(_ input: Input) -> [(provider: AgentProvider, receipt: IntegrationReceipt)] {
        AgentProvider.allCases.compactMap { provider in
            guard input.selected.contains(provider), let receipt = input.receipts[provider],
                  receipt.at >= input.startedAt else { return nil }
            return (provider, receipt)
        }
    }

    /// 첫 실행에 메인 창에 띄우나: 프로젝트가 하나도 없고(보관 포함) 끝낸 적이 없을 때만.
    public static func shouldAutoPresent(projectCount: Int, completed: Bool) -> Bool {
        projectCount == 0 && !completed
    }

    /// 끝냈는지 기억하는 UserDefaults 키
    public static let completedKey = "onboarding.completed"
}
