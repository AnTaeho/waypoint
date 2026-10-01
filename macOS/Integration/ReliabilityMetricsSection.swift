import SwiftUI
import WaypointKit

/// 연동 상태 패널의 기록 지표(TRK-11). 숫자가 없으면 줄을 감춘다.
struct ReliabilityMetricsSection: View {
    let metrics: ReliabilityMetrics

    var body: some View {
        let display = ReliabilityMetrics.summary(metrics.displayMs)
        let resume = ReliabilityMetrics.summary(metrics.resumeSeconds)
        if display != nil || resume != nil || metrics.failures.total > 0 || !metrics.recovery.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("기록 지표").font(Theme.bodyMedium)
                if let display {
                    Text("수신 → 화면 · p95 \(ReliabilityMetrics.duration(display.p95 / 1000)) · 최근 \(display.count)건")
                }
                if let resume {
                    Text("재개 · 중앙값 \(ReliabilityMetrics.duration(resume.p50)) · \(resume.count)회")
                }
                if metrics.failures.total > 0 {
                    Text("연동 실패 · 서버 \(metrics.failures.server) · 형식 \(metrics.failures.invalidInput) · 저장 \(metrics.failures.saveFailed)")
                        .foregroundStyle(Theme.liveText)
                }
                if !metrics.recovery.isEmpty {
                    Text("복구 · 흡수 \(metrics.recovery.absorbed) · 보존 \(metrics.recovery.preserved) · 격리 \(metrics.recovery.quarantined) · 세션 정리 \(metrics.recovery.sessionsClosed)")
                }
            }
            .font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
        }
    }
}
