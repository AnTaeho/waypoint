import SwiftUI
import WaypointKit

/// 작업중 카드 안의 세션 정보: 세션 종류·이름(없으면 ID, 서브에이전트는 에이전트 이름)·컨텍스트 사용률, 최근 파일.
struct BoardSessionBox: View {
    let card: Card
    let session: Session
    @Environment(UsageMonitor.self) private var usage

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // 좁은 칸에서 종류가 두 줄로 꺾이거나 ID가 잘리지 않게, 한 줄에 안 들어가면 ID를 아래 줄로 내린다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs + 2) { kindLabel; idText; SessionContextText(status: status) }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    kindLabel
                    HStack(spacing: Theme.Spacing.xs + 2) { idText; SessionContextText(status: status) }
                }
            }
            .foregroundStyle(Theme.text)
            if let file = SessionFormat.recentFileName(card: card, session: session) {
                Text(file)
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, Theme.Spacing.s + 2)
        .padding(.vertical, Theme.Spacing.s + 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Theme.Radius.box).fill(Theme.bg) }
    }

    private var kindLabel: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Image(systemName: isSubagent ? "arrow.triangle.branch" : "terminal")
                .font(Theme.caption)
            Text(isSubagent ? "\(session.provider.name) · 서브에이전트" : session.provider.name)
                .font(Theme.captionLargeMedium)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var status: SessionStatusLine { usage.status(for: session) }

    private var idText: some View {
        Text(status.label(fallback: identifier))
            .font(status.name == nil ? Theme.monoCaption : Theme.caption)
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .truncationMode(status.name == nil ? .middle : .tail)
            .help(status.name ?? "")
    }

    private var isSubagent: Bool { session.kind == .subagent }

    /// 서브에이전트는 이름(없으면 세션 ID 앞 4자리), 메인 세션은 「sess·7f2a」.
    private var identifier: String {
        if isSubagent, let name = session.agentName, !name.isEmpty { return name }
        return SessionFormat.label(kind: .main, id: session.sourceID, agentName: nil)
    }
}
