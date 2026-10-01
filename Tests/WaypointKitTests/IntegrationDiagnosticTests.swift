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
}
