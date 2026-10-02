import AppKit
import Foundation
import Observation
import SwiftData
import WaypointKit

/// 온보딩 진행 상태. 창을 닫았다 열어도 이어지게 `AppServices`가 들고 있다.
@MainActor @Observable
final class OnboardingModel {
    var isPresented = false
    /// 이 시각 이후 활동의 기록만 「첫 기록」으로 센다
    private(set) var startedAt = Date()
    /// 화면이 고른 단계. 실제로 보일 단계는 `OnboardingProgress`가 정한다
    var requested: OnboardingProgress.Step = .tools
    var selected: Set<AgentProvider> = Set(AgentProvider.allCases)
    /// 프로젝트 단계에서 고른 폴더(정규화한 경로)
    private(set) var chosenRoot: String?
    /// 연결 단계의 설치
    private(set) var install: OnboardingTask?
    /// 도구 단계에서 도구 하나를 다시 설치·해제
    private(set) var toolTask: OnboardingTask?

    /// 시트를 띄우는 메인 창(먼저 뜬 창). 창이 여럿이어도 한 창에만 뜬다
    private(set) var hostWindow: UUID?

    @ObservationIgnored private weak var services: AppServices?

    init(services: AppServices? = nil) {
        self.services = services
    }

    func attach(_ services: AppServices) { self.services = services }

    var home: URL { IntegrationEnvironment.home }

    /// 처음부터 연다. 이미 떠 있으면 그대로 둔다.
    func present(at step: OnboardingProgress.Step = .tools) {
        guard !isPresented else { return }
        startedAt = Date()
        requested = step
        chosenRoot = nil
        install = nil
        toolTask = nil
        isPresented = true
        services?.integration.refresh()
    }

    func close() { isPresented = false }

    /// 메인 창이 뜰 때. 맡은 창이 없으면 이 창이 맡는다
    func claimHost(_ window: UUID) { if hostWindow == nil { hostWindow = window } }
    /// 메인 창이 닫힐 때. 맡은 창이면 놓는다(다음에 보이는 창이 맡는다)
    func releaseHost(_ window: UUID) { if hostWindow == window { hostWindow = nil } }

    /// 이 창에 시트를 보일까
    func shows(in window: UUID) -> Bool { isPresented && (hostWindow == nil || hostWindow == window) }

    /// 「끝」: 다시 자동으로 뜨지 않게 기억한다.
    func finish() {
        UserDefaults.standard.set(true, forKey: OnboardingProgress.completedKey)
        isPresented = false
    }

    static var completed: Bool { UserDefaults.standard.bool(forKey: OnboardingProgress.completedKey) }

    // MARK: 연결

    /// 고른 도구로 연결 계획을 만든다(연결 단계에 들어올 때·고른 도구가 바뀌었을 때).
    func prepareInstall() {
        let tools = AgentProvider.allCases.filter { selected.contains($0) }
        if let install, install.providers == tools, install.action == .install, install.phase != .ready { return }
        install = OnboardingTask(providers: tools, action: .install, home: home) { [weak self] in
            self?.services?.integration.refresh()
        }
    }

    func startToolTask(_ provider: AgentProvider, _ action: IntegrationPlan.Action) {
        toolTask = OnboardingTask(providers: [provider], action: action, home: home) { [weak self] in
            self?.services?.integration.refresh()
        }
    }

    func clearToolTask() { toolTask = nil }

    // MARK: 프로젝트

    /// 폴더를 고른다. 등록된 폴더면 그 프로젝트로 보고, 아니면 등록 창에 초안을 띄운다.
    func choose(folder: URL, context: ModelContext) {
        let root = ProjectMatcher.normalize(folder.path)
        chosenRoot = root
        guard ProjectRegistry.project(atRoot: root, in: context) == nil, let services else { return }
        services.drafts.submit(ProjectDraft.folder(root, taken: ProjectRegistry.takenKeys(in: context)))
    }

    func projectChoice(context: ModelContext) -> OnboardingProgress.ProjectChoice {
        guard let chosenRoot else { return .none }
        if let project = ProjectRegistry.project(atRoot: chosenRoot, in: context) {
            return project.archivedAt == nil ? .registered(key: project.key) : .archived(key: project.key)
        }
        if services?.drafts.drafts.contains(where: { $0.rootPath == chosenRoot }) == true { return .pending }
        return .none
    }

    func pickFolder(context: ModelContext) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "고르기"
        if panel.runModal() == .OK, let url = panel.url {
            choose(folder: url, context: context)
        }
    }
}
