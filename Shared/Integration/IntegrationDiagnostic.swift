import Foundation

/// 공유할 필드를 명시적으로 고른다. 프로젝트명·설정 경로·자유 형식 오류는 포함하지 않는다.
public enum IntegrationDiagnostic {
    public static func text(version: String, environment: String, operatingSystem: String,
                            port: UInt16, serverReady: Bool, history: IntegrationHistory,
                            installations: [AgentProvider: IntegrationInstallation],
                            queue: IntegrationQueue, checkedAt: Date,
                            metrics: ReliabilityMetrics? = nil, coverage: TrackingCoverage? = nil) -> String {
        func time(_ date: Date?) -> String { date?.ISO8601Format() ?? "없음" }
        var lines = [
            "Waypoint 연동 진단", "앱: \(environment)", "버전: \(version)",
            "운영체제: \(operatingSystem)", "점검 시각: \(time(checkedAt))",
            "로컬 포트: \(port)", "서버: \(serverReady ? "실행 중" : "확인 필요")",
            "미처리 기록: \(queue.count)", "기록 읽기: \(queue.unreadable ? "실패" : "정상")",
            "진단 알림: \(history.issue == nil ? "없음" : "있음 (앱에서 확인)")",
            "MCP 마지막 요청: \(time(history.lastMCPAt))"
        ]
        for provider in AgentProvider.allCases {
            let installation: String
            switch installations[provider]?.state {
            case .ready: installation = "설정 확인"
            case .missing: installation = "설정 없음"
            case .attention: installation = "확인 필요"
            case nil: installation = "미점검"
            }
            let receipt = history.hooks[provider.rawValue]
            lines += ["", "\(provider.name)", "사용자 훅: \(installation)",
                      "마지막 활동: \(time(receipt?.at))", "실제 수신: \(time(receipt?.receivedAt))",
                      "재수신 기록: \(receipt.map { $0.replayed ? "예" : "아니오" } ?? "없음")",
                      "수신 프로젝트 연결: \(receipt.map { $0.project == nil ? "미연결" : "연결됨" } ?? "수신 없음")"]
        }
        if let metrics { lines += [""] + metrics.diagnosticLines() }
        if let coverage { lines += [""] + coverage.diagnosticLines() }
        lines += ["", "프로젝트명·파일 경로·세션 ID·대화·오류 원문은 제외했습니다.",
                  "사용자 범위 설정과 실제 수신 기준이며, 신뢰 승인 여부를 증명하지 않습니다."]
        return lines.joined(separator: "\n")
    }
}
