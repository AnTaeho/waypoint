import Foundation
import Testing
@testable import WaypointKit

@Suite struct IntegrationDiagnosticTests {
    @Test func excludesPrivateTextWhilePreservingUsefulStatus() {
        var history = IntegrationHistory()
        history.receive(.codex, at: t0, receivedAt: t0 + 60, project: "PRIVATE-PROJECT", replayed: true)
        history.issue = "private-session at /Users/private/code with secret prompt"
        history.lastMCPAt = t0 + 70
        let installations: [AgentProvider: IntegrationInstallation] = [
            .claude: .init(state: .missing, detail: "/Users/private/settings"),
            .codex: .init(state: .attention, detail: "private-token")
        ]
        var queue = IntegrationQueue(); queue.count = 4; queue.unreadable = true
        let report = IntegrationDiagnostic.text(version: "1.2 · 빌드 3", environment: "Waypoint Dev",
            operatingSystem: "macOS", port: 47822, serverReady: false, history: history,
            installations: installations, queue: queue, checkedAt: t0 + 80)
        for secret in ["PRIVATE-PROJECT", "private-session", "/Users/", "secret prompt", "private-token"] {
            #expect(!report.contains(secret))
        }
        #expect(report.contains("미처리 기록: 4") && report.contains("기록 읽기: 실패"))
        #expect(report.contains("재수신 기록: 예") && report.contains("수신 프로젝트 연결: 연결됨"))
        #expect(report.contains((t0 + 60).ISO8601Format()))
        #expect(report.contains("사용자 훅: 확인 필요") && report.contains("서버: 확인 필요"))
    }

    @Test func noReceiptIsNotReportedAsConnectionOrApproval() {
        let report = IntegrationDiagnostic.text(version: "0.0.1", environment: "Waypoint",
            operatingSystem: "macOS", port: 47821, serverReady: true, history: .init(),
            installations: [.claude: .init(state: .ready, detail: "installed")], queue: .init(), checkedAt: t0)
        #expect(report.contains("사용자 훅: 설정 확인") && report.contains("사용자 훅: 미점검"))
        #expect(report.contains("실제 수신: 없음") && report.contains("수신 프로젝트 연결: 수신 없음"))
        #expect(report.contains("MCP 마지막 요청: 없음") && !report.contains("연결됨"))
    }

    /// 기록 지표(TRK-11)를 더해도 프로젝트명·경로·세션 ID·대화가 들어가지 않는다.
    @Test func diagnosticExportAddsMetricsWithoutPrivateText() {
        var history = IntegrationHistory()
        history.receive(.claude, at: t0, receivedAt: t0 + 1, project: "PRIVATE-PROJECT", replayed: false)
        history.issue = "11111111-1111-4111-8111-111111111111 /Users/private/secret.swift 비밀 요청"
        var m = ReliabilityMetrics(since: t0)
        for ms in [3.0, 4, 5, 6, 200] { m.recordReceipt(receivedAt: t0, savedAt: t0 + ms / 2000, shownAt: t0 + ms / 1000) }
        m.recordResume(seconds: 45)
        m.failures.invalidInput = 2
        m.recovery = .init()
        m.recovery.absorbed = 12
        let report = IntegrationDiagnostic.text(version: "0.0.1", environment: "Waypoint Dev", operatingSystem: "macOS",
            port: 47822, serverReady: true, history: history, installations: [:], queue: .init(),
            checkedAt: t0 + 2, metrics: m)
        for secret in ["PRIVATE-PROJECT", "11111111", "/Users/", "secret", "비밀 요청"] {
            #expect(!report.contains(secret), "\(secret)")
        }
        #expect(report.contains("수신→화면: 5건 · 중앙값 5.0 ms · p95 200 ms · 최대 200 ms"))
        #expect(report.contains("재개 시간: 1회 · 중앙값 45초"))
        #expect(report.contains("연동 실패: 서버 시작 0 · 형식 오류 2 · 저장 실패 0"))
        #expect(report.contains("복구: 미처리 기록 흡수 12 · 보존 0 · 격리 0 · 세션 정리 0"))
        // 지표 없이 부르면 예전 내용 그대로
        let plain = IntegrationDiagnostic.text(version: "0.0.1", environment: "Waypoint", operatingSystem: "macOS",
            port: 47821, serverReady: true, history: .init(), installations: [:], queue: .init(), checkedAt: t0)
        #expect(!plain.contains("기록 지표"))
    }
}
