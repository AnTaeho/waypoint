import Foundation
import Testing
@testable import WaypointKit

@Suite struct OnboardingProgressTests {
    typealias Step = OnboardingProgress.Step
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let ready = IntegrationInstallation(state: .ready, detail: "설정됨")
    let missing = IntegrationInstallation(state: .missing, detail: "설정 없음")

    func input(_ step: Step, selected: Set<AgentProvider> = [.claude, .codex],
               installations: [AgentProvider: IntegrationInstallation]? = nil,
               receipts: [AgentProvider: IntegrationReceipt] = [:], serverProblem: String? = nil,
               projectCount: Int = 0, project: OnboardingProgress.ProjectChoice = .registered(key: "TRK"),
               installBlock: String? = nil) -> OnboardingProgress.Input {
        .init(requested: step, selected: selected, installations: installations ?? [.claude: ready, .codex: ready],
              receipts: receipts, startedAt: start, serverProblem: serverProblem, projectCount: projectCount,
              project: project, installBlock: installBlock)
    }

    func receipt(_ offset: TimeInterval, project: String? = "TRK", replayed: Bool = false) -> IntegrationReceipt {
        IntegrationReceipt(at: start + offset, receivedAt: start + max(offset, 0) + 1, project: project, replayed: replayed)
    }

    @Test func toolsNeedAtLeastOneSelection() {
        let none = OnboardingProgress(input(.tools, selected: []))
        #expect(none.step == .tools && none.blocker == .noToolSelected)
        // 고른 것이 없으면 뒤 단계를 요청해도 도구 단계로 돌아간다.
        #expect(OnboardingProgress(input(.receive, selected: [])).step == .tools)
        #expect(OnboardingProgress(input(.tools)).blocker == nil)
    }

    @Test func installWaitsForEverySelectedTool() {
        let partial = OnboardingProgress(input(.install, installations: [.claude: ready, .codex: missing]))
        #expect(partial.step == .install && partial.blocker == .notInstalled([.codex]))
        // 고르지 않은 도구는 보지 않는다.
        #expect(OnboardingProgress(input(.install, selected: [.claude], installations: [.claude: ready, .codex: missing])).blocker == nil)
        // 진단 결과가 아직 없으면 미설치로 본다.
        #expect(OnboardingProgress(input(.install, installations: [.claude: ready])).blocker == .notInstalled([.codex]))
        // 앞 단계가 막히면 그 단계를 보인다.
        let later = OnboardingProgress(input(.receive, installations: [.claude: missing, .codex: ready]))
        #expect(later.step == .install && later.blocker == .notInstalled([.claude]))
    }

    @Test func installAttentionShowsDetail() {
        let off = IntegrationInstallation(state: .attention, detail: "Codex 설정에서 연결 꺼짐")
        let progress = OnboardingProgress(input(.install, installations: [.claude: ready, .codex: off]))
        #expect(progress.blocker == .attention(.codex, "Codex 설정에서 연결 꺼짐"))
        #expect(OnboardingText.blocker(progress.blocker!) == "Codex · Codex 설정에서 연결 꺼짐")
    }

    @Test func devBlockOnlyMattersWhenSomethingIsMissing() {
        let blocked = OnboardingProgress(input(.install, installations: [.claude: missing, .codex: ready],
                                               installBlock: IntegrationHomePolicy.devBlockReason))
        #expect(blocked.blocker == .installBlocked(IntegrationHomePolicy.devBlockReason))
        // 평소용 포트로 연결돼 있어 확인이 필요한 상태도 Dev에서는 고칠 수 없다(그 까닭을 보인다).
        let attention = IntegrationInstallation(state: .attention, detail: "SessionStart 연결 포트가 앱 포트 47822와 다름")
        #expect(OnboardingProgress(input(.install, installations: [.claude: attention, .codex: ready],
                                         installBlock: IntegrationHomePolicy.devBlockReason)).blocker
                == .installBlocked(IntegrationHomePolicy.devBlockReason))
        // 이미 연결돼 있으면 막혀도 다음으로 간다.
        #expect(OnboardingProgress(input(.install, installBlock: IntegrationHomePolicy.devBlockReason)).blocker == nil)
    }

    @Test func projectStep() {
        #expect(OnboardingProgress(input(.project, project: .none)).blocker == .noProject)
        // 이미 등록된 프로젝트가 있으면 고르지 않아도 넘어간다(다시 열기).
        #expect(OnboardingProgress(input(.project, projectCount: 3, project: .none)).blocker == nil)
        #expect(OnboardingProgress(input(.project, project: .pending)).blocker == .pendingRegistration)
        #expect(OnboardingProgress(input(.project, projectCount: 3, project: .archived(key: "OLD"))).blocker == .archivedProject("OLD"))
        #expect(OnboardingProgress(input(.receive, project: .none)).step == .project)
    }

    @Test func receiveWaitsForLinkedRecordAfterStart() {
        let waiting = OnboardingProgress(input(.receive))
        #expect(waiting.step == .receive && waiting.blocker == .waiting)
        // 시작 전 활동의 기록(재전송 포함)은 세지 않는다.
        let old = OnboardingProgress(input(.receive, receipts: [.claude: receipt(-60, replayed: true)]))
        #expect(old.blocker == .waiting && old.linkedReceipt == nil)
        // 등록 밖 폴더의 기록
        let unlinked = OnboardingProgress(input(.receive, receipts: [.codex: receipt(5, project: nil)]))
        #expect(unlinked.step == .receive && unlinked.blocker == .unlinked(.codex))
        // 프로젝트에 연결된 기록이 오면 끝 단계로 넘어간다.
        let done = OnboardingProgress(input(.receive, receipts: [.codex: receipt(5, project: nil), .claude: receipt(9)]))
        #expect(done.step == .done && done.blocker == nil)
        #expect(done.linkedReceipt?.provider == .claude && done.linkedReceipt?.receipt.project == "TRK")
    }

    @Test func receiveIgnoresUnselectedTools() {
        let progress = OnboardingProgress(input(.receive, selected: [.codex], receipts: [.claude: receipt(5)]))
        #expect(progress.step == .receive && progress.blocker == .waiting)
    }

    @Test func serverDownBlocksReceiveAndDone() {
        let down = OnboardingProgress(input(.receive, receipts: [.claude: receipt(5)], serverProblem: "기록 받을 준비 중"))
        #expect(down.step == .receive && down.blocker == .serverDown("기록 받을 준비 중"))
        // 끝 단계를 요청해도 기록 조건이 안 되면 수신 단계
        #expect(OnboardingProgress(input(.done)).step == .receive)
        #expect(OnboardingText.serverProblem(.ready) == nil)
        #expect(OnboardingText.serverProblem(.failed("Address already in use"))?.contains("Address already in use") == true)
    }

    @Test func autoPresentOnlyWithoutProjectsAndNotCompleted() {
        #expect(OnboardingProgress.shouldAutoPresent(projectCount: 0, completed: false))
        #expect(!OnboardingProgress.shouldAutoPresent(projectCount: 0, completed: true))
        #expect(!OnboardingProgress.shouldAutoPresent(projectCount: 2, completed: false))
    }

    @Test func stepOrder() {
        #expect(Step.tools.next == .install && Step.receive.next == .done && Step.done.next == .done)
        #expect(Step.install.previous == .tools && Step.tools.previous == .tools)
    }
}

@Suite struct IntegrationHomePolicyTests {
    let real = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    @Test func overrideOnlyWhenAllowed() {
        let env = [IntegrationHomePolicy.environmentKey: "/tmp/probe home"]
        #expect(IntegrationHomePolicy.home(environment: env, allowOverride: true, realHome: real).path == "/tmp/probe home")
        // Release는 변수를 무시한다.
        #expect(IntegrationHomePolicy.home(environment: env, allowOverride: false, realHome: real) == real)
        #expect(IntegrationHomePolicy.home(environment: [IntegrationHomePolicy.environmentKey: " "], allowOverride: true, realHome: real) == real)
        #expect(IntegrationHomePolicy.home(environment: [:], allowOverride: true, realHome: real) == real)
    }

    @Test func devBlockedOnRealHomeOnly() throws {
        #expect(IntegrationHomePolicy.installBlock(instance: .dev, home: real, realHome: real) == IntegrationHomePolicy.devBlockReason)
        // 끝 빗금·`.` 경로도 같은 홈
        let same = URL(fileURLWithPath: "/Users/me/./", isDirectory: true)
        #expect(IntegrationHomePolicy.installBlock(instance: .dev, home: same, realHome: real) != nil)
        #expect(IntegrationHomePolicy.installBlock(instance: .dev, home: URL(fileURLWithPath: "/tmp/probe"), realHome: real) == nil)
        #expect(IntegrationHomePolicy.installBlock(instance: .stable, home: real, realHome: real) == nil)
    }

    @Test func symlinkedHomeIsTheSameHome() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("home-policy-\(UUID().uuidString.prefix(8))")
        let target = base.appendingPathComponent("real", isDirectory: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(IntegrationHomePolicy.installBlock(instance: .dev, home: link, realHome: target) != nil)
    }

    @Test func releaseDevWithOverrideIgnoredStaysBlocked() {
        let env = [IntegrationHomePolicy.environmentKey: "/tmp/probe"]
        let home = IntegrationHomePolicy.home(environment: env, allowOverride: false, realHome: real)
        #expect(IntegrationHomePolicy.installBlock(instance: .dev, home: home, realHome: real) != nil)
    }
}
