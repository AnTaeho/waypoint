import SwiftUI
import WaypointKit

/// 작업중 카드 안의 세션 정보: 세션 종류·ID(서브에이전트는 이름), 최근 파일.
struct BoardSessionBox: View {
    let card: Card
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // 좁은 칸에서 종류가 두 줄로 꺾이거나 ID가 잘리지 않게, 한 줄에 안 들어가면 ID를 아래 줄로 내린다.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xs + 2) { kindLabel; idText }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) { kindLabel; idText }
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
            Text(isSubagent ? "서브에이전트" : "Claude Code")
                .font(Theme.captionLargeMedium)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var idText: some View {
        Text(identifier)
            .font(Theme.monoCaption)
            .foregroundStyle(Theme.textMuted)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var isSubagent: Bool { session.kind == .subagent }

    /// 서브에이전트는 이름(없으면 세션 ID 앞 4자리), 메인 세션은 「sess·7f2a」.
    private var identifier: String {
        if isSubagent, let name = session.agentName, !name.isEmpty { return name }
        return SessionFormat.label(kind: .main, id: session.id, agentName: nil)
    }
}
