import SwiftUI
import WaypointKit

/// 사이드바 맨 아래 사용량 게이지. 도구(Claude·Codex)마다 묶음 하나, 한도마다 한 줄.
/// 설정에서 끈 도구와 기록이 없는 도구는 묶음째 숨기고, 남는 것이 없으면 아무것도 그리지 않는다.
struct UsageGaugeView: View {
    @Environment(UsageMonitor.self) private var monitor
    @AppStorage(UsageSettings.showClaudeKey) private var showClaude = true
    @AppStorage(UsageSettings.showCodexKey) private var showCodex = true

    var body: some View {
        let groups = monitor.groups(showClaude: showClaude, showCodex: showCodex)
        if !groups.isEmpty {
            // 초기화 시각이 지나거나 기록이 오래되는 것을 1분마다 다시 판정한다.
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(alignment: .leading, spacing: Theme.Usage.groupSpacing) {
                    ForEach(groups, id: \.tool) { group in
                        UsageGroupView(group: group, now: timeline.date)
                    }
                }
                // 이름표를 위 프로젝트 키 열과 맞춘다.
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.m)
            }
        }
    }
}

/// 묶음 하나: 머리 「Claude」 + 한도별 줄. 마우스를 올리면 「12분 전 기준」.
private struct UsageGroupView: View {
    let group: UsageGroup
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(group.tool.title)
                .font(Theme.tableHeader)
                .foregroundStyle(Theme.textMuted)
            ForEach(group.limits, id: \.minutes) { limit in
                UsageGaugeRow(limit: limit, now: now)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(group.isStale(now: now) ? Theme.Usage.staleOpacity : 1)
        .contentShape(Rectangle())
        .help(UsageFormat.basis(capturedAt: group.capturedAt, now: now))
    }
}

/// 「5시간 ▬▬▬── 42%」, 아래에 초기화 시각 「↻ 오후 3:20」(모르거나 지났으면 생략).
private struct UsageGaugeRow: View {
    let limit: UsageGroup.Limit
    let now: Date

    var body: some View {
        let window = limit.window
        let isHigh = window.percent(at: now) >= Theme.Usage.highPercent
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.s) {
                Text(limit.label)
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
            if let reset = UsageFormat.resetShort(window, now: now) {
                Label(reset, systemImage: Theme.Usage.resetSymbol)
                    .labelStyle(UsageResetLabelStyle())
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .padding(.leading, Theme.Size.gaugeLabelWidth + Theme.Spacing.s)
            }
        }
    }
}

/// 아이콘과 글자 사이를 좁게
private struct UsageResetLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
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
