import Foundation
import Testing
@testable import WaypointKit

/// 첫 연결 지표(TRK-45): 시도별 단계 시각·실패 지점·다시 시도·요약·저장 형식.
@Suite struct OnboardingMetricsTests {
    private func input(_ requested: OnboardingProgress.Step = .tools,
                       installs: [AgentProvider: IntegrationInstallation.State] = [:],
                       receipts: [AgentProvider: IntegrationReceipt] = [:],
                       project: OnboardingProgress.ProjectChoice = .none, projectCount: Int = 0,
                       server: String? = nil, block: String? = nil, startedAt: Date = t0) -> OnboardingProgress {
        OnboardingProgress(.init(requested: requested, selected: Set(AgentProvider.allCases),
                                 installations: installs.mapValues { IntegrationInstallation(state: $0, detail: "") },
                                 receipts: receipts, startedAt: startedAt, serverProblem: server,
                                 projectCount: projectCount, project: project, installBlock: block))
    }

    private let ready: [AgentProvider: IntegrationInstallation.State] = [.claude: .ready, .codex: .ready]

    @Test func recordsStagesInOrder() throws {
        var m = OnboardingMetrics()
        m.start(at: t0)
        var previous: OnboardingProgress.Blocker?
        func see(_ p: OnboardingProgress, _ at: TimeInterval) { m.observe(p, previous: previous, at: t0 + at); previous = p.blocker }
        see(input(.tools), 0)
        see(input(.install), 5)
        m.installed(.claude, at: t0 + 20, attempt: t0)      // 적용 성공(설치 작업이 알림)
        see(input(.install, installs: ready), 30)           // codex는 판정으로 확인
        see(input(.project, installs: ready), 31)
        see(input(.project, installs: ready, project: .registered(key: "APP"), projectCount: 1), 50)
        see(input(.receive, installs: ready, project: .registered(key: "APP"), projectCount: 1), 51)
        let claude = IntegrationReceipt(at: t0 + 80, receivedAt: t0 + 81, project: "APP", replayed: false)
        see(input(.receive, installs: ready, receipts: [.claude: claude], project: .registered(key: "APP"), projectCount: 1), 82)
        let codex = IntegrationReceipt(at: t0 + 120, receivedAt: t0 + 121, project: "APP", replayed: false)
        see(input(.receive, installs: ready, receipts: [.claude: claude, .codex: codex],
                  project: .registered(key: "APP"), projectCount: 1), 122)
        m.finish(at: t0 + 130, attempt: t0)

        let a = try #require(m.attempts.last)
        #expect(a.installed.claude == t0 + 20 && a.installed.codex == t0 + 30)
        #expect(a.projectAt == t0 + 50)
        #expect(a.firstRecord.claude == t0 + 81 && a.firstRecord.codex == t0 + 121)
        #expect(a.timeToFirstRecord(.claude) == 81 && a.timeToAnyRecord == 81)
        #expect(a.finishedAt == t0 + 130 && a.lastStage == .done && a.furthestStage == .done)
        #expect(a.failures.isEmpty && a.retries == 0)
        // 끝난 시도는 더 바뀌지 않는다
        m.close(at: t0 + 140, attempt: t0)
        m.retried(attempt: t0)
        #expect(m.attempts.last?.closedAt == nil && m.attempts.last?.retries == 0)
    }

    @Test func ignoresRecordsBeforeStartAndUnlinkedRecordsCountAsFailure() throws {
        var m = OnboardingMetrics()
        m.start(at: t0)
        let old = IntegrationReceipt(at: t0 - 10, receivedAt: t0 + 1, project: "APP", replayed: true)
        m.observe(input(.receive, installs: ready, receipts: [.claude: old], projectCount: 1), previous: nil, at: t0 + 2)
        #expect(m.attempts[0].firstRecord == .init())
        let outside = IntegrationReceipt(at: t0 + 3, receivedAt: t0 + 3, project: nil, replayed: false)
        let p = input(.receive, installs: ready, receipts: [.codex: outside], projectCount: 1)
        m.observe(p, previous: .waiting, at: t0 + 4)
        m.observe(p, previous: p.blocker, at: t0 + 5) // 같은 막힘이 다시 그려져도 늘지 않는다
        #expect(m.attempts[0].firstRecord == .init())
        #expect(m.attempts[0].failures == [.init(stage: .receive, reason: .unlinked, tool: .codex, at: t0 + 4)])
    }

    @Test func retriesAndFailureClassification() throws {
        var m = OnboardingMetrics()
        m.start(at: t0)
        m.fail(.install, .init(IntegrationInstallError.writeFailed(path: "/x", reason: "r", rolledBack: true, rollbackFailures: [])),
               tool: .claude, at: t0 + 1, attempt: t0)
        m.retried(attempt: t0)
        m.fail(.install, .init(IntegrationInstallError.writeFailed(path: "/y", reason: "s", rolledBack: false, rollbackFailures: ["a"])),
               tool: .claude, at: t0 + 2, attempt: t0)
        m.retried(attempt: t0)
        m.fail(.install, try #require(.init(IntegrationInstaller.StepOutcome.failed("timeout"))), tool: .claude, at: t0 + 3, attempt: t0)
        let a = m.attempts[0]
        #expect(a.retries == 2)
        #expect(a.failures.map(\.reason) == [.writeFailed, .commandFailed])
        #expect(a.failures[0].count == 2 && a.failures[0].at == t0 + 1)

        // 분류
        #expect(OnboardingMetrics.Reason(IntegrationInstallError.conflict("x")) == .conflict)
        #expect(OnboardingMetrics.Reason(IntegrationInstallError.unreadable(path: "p", reason: "r")) == .unreadable)
        #expect(OnboardingMetrics.Reason(IntegrationInstallError.missingResource("x")) == .missingResource)
        #expect(OnboardingMetrics.Reason(IntegrationInstallError.changedSincePlan(path: "p")) == .changedSincePlan)
        #expect(OnboardingMetrics.Reason(IntegrationInstallError.backupFailed("x")) == .backupFailed)
        #expect(OnboardingMetrics.Reason(error: CocoaError(.fileNoSuchFile)) == .setupUnavailable)
        #expect(OnboardingMetrics.Reason(IntegrationInstaller.StepOutcome.executableMissing) == .commandMissing)
        #expect(OnboardingMetrics.Reason(IntegrationInstaller.StepOutcome.done) == nil)
        #expect(OnboardingMetrics.Reason.blocker(.installBlocked("x"))! == (.devBlocked, nil))
        #expect(OnboardingMetrics.Reason.blocker(.attention(.codex, "d"))! == (.attention, .codex))
        #expect(OnboardingMetrics.Reason.blocker(.serverDown("x"))! == (.serverDown, nil))
        #expect(OnboardingMetrics.Reason.blocker(.archivedProject("K"))! == (.archivedProject, nil))
        #expect(OnboardingMetrics.Reason.blocker(.waiting) == nil)
        #expect(OnboardingMetrics.Reason.blocker(.notInstalled([.claude])) == nil)
        #expect(OnboardingMetrics.Reason.blocker(.pendingRegistration) == nil)
    }

    @Test func blockersFromProgressAreFailuresAtTheirStage() {
        var m = OnboardingMetrics()
        m.start(at: t0)
        let blocked = input(.install, block: IntegrationHomePolicy.devBlockReason)
        m.observe(blocked, previous: nil, at: t0 + 1)
        let down = input(.receive, installs: ready, projectCount: 1, server: "기록 받을 준비 중")
        m.observe(down, previous: blocked.blocker, at: t0 + 2)
        #expect(m.attempts[0].failures.map(\.stage) == [.install, .receive])
        #expect(m.attempts[0].failures.map(\.reason) == [.devBlocked, .serverDown])
        #expect(m.attempts[0].lastStage == .receive && m.attempts[0].furthestStage == .receive)
    }

    @Test func closeLeavesAttemptUnfinishedAndSummaryFindsStops() throws {
        var m = OnboardingMetrics()
        // 1: 연결에서 닫음
        m.start(at: t0)
        m.reach(.install, attempt: t0)
        m.close(at: t0 + 10, attempt: t0)
        // 2: 연결에서 앱이 꺼짐(열린 채)
        m.start(at: t0 + 100)
        m.reach(.install, attempt: t0 + 100)
        // 3: 끝냄, 첫 기록 60초
        m.start(at: t0 + 200)
        m.firstRecord(.claude, at: t0 + 260, attempt: t0 + 200)
        m.finish(at: t0 + 270, attempt: t0 + 200)
        // 4: 끝냄, 첫 기록 100초(codex가 먼저)
        m.start(at: t0 + 300)
        m.firstRecord(.codex, at: t0 + 400, attempt: t0 + 300)
        m.firstRecord(.claude, at: t0 + 450, attempt: t0 + 300)
        m.finish(at: t0 + 460, attempt: t0 + 300)
        // 5: 프로젝트에서 닫음
        m.start(at: t0 + 500)
        m.reach(.project, attempt: t0 + 500)
        m.close(at: t0 + 510, attempt: t0 + 500)
        // 6: 진행 중(멈춘 단계에서 뺀다)
        m.start(at: t0 + 600)
        m.reach(.project, attempt: t0 + 600)

        #expect(m.attempts[0].closedAt == t0 + 10 && m.attempts[0].finishedAt == nil)
        let s = m.summary
        #expect(s.attempts == 6 && s.finished == 2)
        #expect(s.medianToFirstRecord == 80)
        #expect(s.mostStopped == .init(stage: .install, count: 2))
        #expect(s.last?.startedAt == t0 + 600)
        // 홀수 개 중앙값
        m.start(at: t0 + 700)
        m.firstRecord(.claude, at: t0 + 790, attempt: t0 + 700)
        m.finish(at: t0 + 800, attempt: t0 + 700)
        #expect(m.summary.medianToFirstRecord == 90)
        #expect(OnboardingMetrics().summary.mostStopped == nil && OnboardingMetrics().summary.medianToFirstRecord == nil)
    }

    @Test func keepsOnlyRecentAttempts() {
        var m = OnboardingMetrics()
        for i in 0..<(OnboardingMetrics.attemptLimit + 5) { m.start(at: t0 + Double(i)) }
        #expect(m.attempts.count == OnboardingMetrics.attemptLimit)
        #expect(m.attempts.first?.startedAt == t0 + 5)
        // 밀려난 시도에는 쓰지 않는다
        m.retried(attempt: t0)
        #expect(m.attempts.allSatisfy { $0.retries == 0 })
    }

    @Test func storedShapeHoldsNumbersOnlyAndToleratesUnknownValues() throws {
        var r = ReliabilityMetrics(since: t0)
        r.onboarding.start(at: t0)
        r.onboarding.reach(.receive, attempt: t0)
        r.onboarding.installed(.codex, at: t0 + 1, attempt: t0)
        r.onboarding.projectRegistered(at: t0 + 2, attempt: t0)
        r.onboarding.firstRecord(.claude, at: t0 + 3, attempt: t0)
        r.onboarding.fail(.install, .commandMissing, tool: .claude, at: t0 + 1, attempt: t0)
        r.onboarding.retried(attempt: t0)
        r.onboarding.close(at: t0 + 4, attempt: t0)
        let data = try JSONEncoder().encode(r)
        #expect(try JSONDecoder().decode(ReliabilityMetrics.self, from: data) == r)
        func strings(_ value: Any) -> [String] {
            switch value {
            case let s as String: [s]
            case let a as [Any]: a.flatMap(strings)
            case let d as [String: Any]: d.values.flatMap(strings)
            default: []
            }
        }
        #expect(strings(try JSONSerialization.jsonObject(with: data)).isEmpty)
        // 키 이름도 고정한다(문서에 적는 필드)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attempt = try #require(((object["onboarding"] as? [String: Any])?["attempts"] as? [[String: Any]])?.first)
        #expect(Set(attempt.keys) == ["startedAt", "lastStage", "furthestStage", "installed", "projectAt",
                                      "firstRecord", "closedAt", "retries", "failures"])
        #expect(Set(((attempt["failures"] as? [[String: Any]])?.first ?? [:]).keys) == ["stage", "reason", "tool", "at", "count"])

        // 옛 metrics.json(온보딩 없음)
        let older = try JSONDecoder().decode(ReliabilityMetrics.self, from: Data(#"{"since":1,"saveMs":[2]}"#.utf8))
        #expect(older.saveMs == [2] && older.onboarding.attempts.isEmpty)
        // 모르는 단계·까닭 값은 기본값으로, 깨진 onboarding은 버리고 나머지 지표는 살린다
        let future = #"{"since":1,"onboarding":{"attempts":[{"startedAt":5,"lastStage":9,"failures":[{"stage":1,"reason":99,"at":5,"count":1}]}]}}"#
        let a = try #require(try JSONDecoder().decode(ReliabilityMetrics.self, from: Data(future.utf8)).onboarding.attempts.first)
        #expect(a.lastStage == .tools && a.failures.first?.reason == .other)
        let broken = try JSONDecoder().decode(ReliabilityMetrics.self, from: Data(#"{"since":1,"saveMs":[3],"onboarding":7}"#.utf8))
        #expect(broken.saveMs == [3] && broken.onboarding.attempts.isEmpty)
    }

    @Test func diagnosticLinesHaveNoPathsOrKeys() {
        var r = ReliabilityMetrics(since: t0)
        #expect(r.onboarding.diagnosticLines() == ["첫 연결: 시도 없음"])
        r.onboarding.start(at: t0)
        r.onboarding.installed(.claude, at: t0 + 12, attempt: t0)
        r.onboarding.projectRegistered(at: t0 + 30, attempt: t0)
        r.onboarding.firstRecord(.claude, at: t0 + 65, attempt: t0)
        r.onboarding.fail(.install, .commandFailed, tool: .claude, at: t0 + 10, attempt: t0)
        r.onboarding.retried(attempt: t0)
        r.onboarding.finish(at: t0 + 70, attempt: t0)
        let lines = r.onboarding.diagnosticLines()
        #expect(lines[0] == "첫 연결: 시도 1회 · 끝냄 1회")
        #expect(lines[1] == "마지막 시도: \(t0.ISO8601Format()) 시작 · 단계 끝 · 끝냄 · 다시 시도 1회")
        #expect(lines[2] == "마지막 시도 시작→첫 기록: Claude Code 65초 · Codex 없음")
        #expect(lines[3] == "마지막 시도 시작→연결·프로젝트: Claude Code 연결 12초 · Codex 연결 없음 · 프로젝트 30초")
        #expect(lines[4] == "끝낸 시도 시작→첫 기록 중앙값: 65초 (1회)")
        #expect(lines[5] == "가장 많이 멈춘 단계: 없음")
        #expect(lines[6] == "마지막 시도 실패: 연결·등록 명령 실패·Claude Code 1회")
        #expect(r.onboarding.panelLines() == ["첫 기록까지 · 최근 65초 · 중앙값 65초 (1회)"])
        r.onboarding.start(at: t0 + 100)
        r.onboarding.reach(.install, attempt: t0 + 100)
        r.onboarding.close(at: t0 + 110, attempt: t0 + 100)
        #expect(r.onboarding.panelLines() == ["첫 기록까지 · 중앙값 65초 (1회)", "자주 멈춘 단계 · 연결 (1회)"])
        #expect(OnboardingMetrics().panelLines().isEmpty)
        let text = IntegrationDiagnostic.text(version: "1", environment: "Dev", operatingSystem: "macOS", port: 47822,
                                              serverReady: true, history: .init(), installations: [:], queue: .init(),
                                              checkedAt: t0, metrics: r)
        #expect(text.contains("첫 연결: 시도 2회 · 끝냄 1회") && !text.contains("/"))
    }
}
