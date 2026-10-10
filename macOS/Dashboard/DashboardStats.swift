import SwiftUI
import WaypointKit

struct DashboardStats: View {
    let overview: DashboardOverview

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xl) { metrics }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: Theme.Spacing.xl) { metrics }
        }
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var metrics: some View {
        metric("작업 중", count: overview.liveCount, color: Theme.liveText)
        if overview.waitingCount > 0 {
            metric("내 답 기다림", count: overview.waitingCount, color: Theme.Situation.waitingText)
        }
        metric("대기·활동 없음", count: overview.stalledCount, color: Theme.text)
        metric("다음 할 일", count: overview.nextCount, color: Theme.next)
        metric("오늘 완료", count: overview.doneTodayCount, color: Theme.done)
    }

    private func metric(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title).font(Theme.caption).foregroundStyle(Theme.textMuted)
            Text("\(count)").font(Theme.detailTitle).foregroundStyle(color).monospacedDigit()
        }
        .frame(minWidth: Theme.Dashboard.metricMinWidth, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
