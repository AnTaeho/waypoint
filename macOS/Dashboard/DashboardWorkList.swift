import SwiftUI
import WaypointKit

struct DashboardWorkList: View {
    let rows: [DashboardRow]
    let now: Date
    @Binding var provider: AgentProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(); filter }
                VStack(alignment: .leading, spacing: Theme.Spacing.m) { title; filter }
            }
            if rows.isEmpty {
                DashboardEmpty(message: provider == nil ? "진행 중인 작업이 없습니다." : "이 도구에서 진행 중인 작업이 없습니다.")
            }
            ForEach(rows) { row in
                DashboardWorkTile(row: row, now: now)
                    .padding(.leading, isNested(row) ? Theme.Spacing.indent : 0)
            }
        }
    }

    private func isNested(_ row: DashboardRow) -> Bool {
        row.depth > 0 && rows.contains { $0.session === row.session.parent }
    }

    private var title: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("진행 중인 작업").font(Theme.sectionLarge)
            Text("\(rows.count)").font(Theme.caption).foregroundStyle(Theme.textMuted)
        }
    }

    private var filter: some View {
        Picker("에이전트", selection: $provider) {
            Text("전체").tag(Optional<AgentProvider>.none)
            Text("Claude").tag(Optional(AgentProvider.claude))
            Text("Codex").tag(Optional(AgentProvider.codex))
        }
        .pickerStyle(.segmented).labelsHidden()
        .frame(width: Theme.Dashboard.filterWidth)
    }
}

struct DashboardEmpty: View {
    let message: String
    var body: some View {
        Text(message).font(Theme.body).foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
            .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
    }
}
