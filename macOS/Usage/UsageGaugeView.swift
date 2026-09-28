import SwiftUI
import WaypointKit

/// 사이드바 맨 아래 사용량 게이지 두 줄(5시간·7일). 기록이 없으면 아무것도 그리지 않는다.
struct UsageGaugeView: View {
    @Environment(UsageMonitor.self) private var monitor

    var body: some View {
        if let snapshot = monitor.snapshot {
            // 초기화 시각이 지나거나 기록이 오래되는 것을 1분마다 다시 판정한다.
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                content(snapshot, now: timeline.date)
            }
        }
    }

    private func content(_ snapshot: UsageSnapshot, now: Date) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if let window = snapshot.fiveHour {
                UsageGaugeRow(label: UsageFormat.fiveHourLabel, window: window, capturedAt: snapshot.capturedAt, now: now)
            }
            if let window = snapshot.sevenDay {
                UsageGaugeRow(label: UsageFormat.sevenDayLabel, window: window, capturedAt: snapshot.capturedAt, now: now)
            }
        }
        // 이름표를 위 프로젝트 키 열과 맞춘다.
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .opacity(snapshot.isStale(now: now) ? Theme.Usage.staleOpacity : 1)
    }
}

private struct UsageGaugeRow: View {
    let label: String
    let window: UsageSnapshot.Window
    let capturedAt: Date
    let now: Date

    var body: some View {
        let isHigh = window.percent(at: now) >= Theme.Usage.highPercent
        HStack(spacing: Theme.Spacing.s) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(width: Theme.Size.gaugeLabelWidth, alignment: .leading)
            UsageBar(fraction: window.fraction(at: now), fill: isHigh ? Theme.liveText : Theme.live)
            Text(UsageFormat.percent(window, now: now))
                .font(isHigh ? Theme.tableHeader : Theme.caption)
                .foregroundStyle(isHigh ? Theme.liveText : Theme.textSecondary)
                .monospacedDigit()
                .frame(width: Theme.Size.gaugeValueWidth, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .help(UsageFormat.help(window, capturedAt: capturedAt, now: now) ?? "")
    }
}

private struct UsageBar: View {
    let fraction: Double
    let fill: Color

    var body: some View {
        Capsule()
            .fill(Theme.gaugeTrack)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: fraction > 0 ? max(proxy.size.height, proxy.size.width * fraction) : 0)
                }
            }
            .frame(height: Theme.Size.gaugeBar)
    }
}
