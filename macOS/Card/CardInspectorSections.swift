import SwiftUI
import WaypointKit

/// 연결된 카드 한 줄의 관계(「상위」「하위」).
struct RelatedCard: Identifiable {
    let card: Card
    let relation: String
    var id: UUID { card.id }
}

/// 서브에이전트 세션과 그 세션이 붙은 카드.
private struct SubagentLink: Identifiable {
    let session: Session
    let card: Card
    var id: String { "\(session.id)|\(card.id.uuidString)" }
}

/// 지금 연결된 세션 한 개: 점·종류·ID, 거기서 갈라진 서브에이전트(→ 카드), 폴더·브랜치.
struct ConnectedSessionBox: View {
    let session: Session
    let now: Date
    /// 이 세션이 다른 작업과 같이 만지는 파일(TRK-17)
    var overlaps: [WorkOverlap.Overlap] = []
    let open: (Card) -> Void

    var body: some View {
        let state = SessionRules.state(of: session, now: now)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                WorkStateDot(state: state == .live ? .live : .stalled)
                Text(session.kind == .subagent ? "\(session.provider.name) · 서브에이전트" : session.provider.name)
                    .font(Theme.bodyStrong)
                Text(identifier(session))
                    .font(Theme.monoCaption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Text(SessionFormat.activityText(session, now: now))
                .font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
            OverlapBadge(overlaps: overlaps)
            ForEach(subagentLinks) { item in
                Button { open(item.card) } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "arrow.triangle.branch")
                        Text(identifier(item.session)).font(Theme.mono)
                        Text("→ \(item.card.displayID)")
                    }
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, Theme.Spacing.l + 2)
            }
            Text(place)
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(Theme.Spacing.rowH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(state == .live ? Theme.live : Theme.border, lineWidth: Theme.Size.liveBorder)
        }
    }

    private func identifier(_ s: Session) -> String {
        if s.kind == .subagent, let name = s.agentName, !name.isEmpty { return name }
        return SessionFormat.label(kind: .main, id: s.sourceID, agentName: nil)
    }

    /// 이 세션에서 갈라진, 아직 끝나지 않은 서브에이전트가 붙어 있는 카드들.
    private var subagentLinks: [SubagentLink] {
        (session.children ?? [])
            .filter { SessionRules.state(of: $0, now: now) != .ended }
            .sorted { $0.startedAt < $1.startedAt }
            .flatMap { child in child.openCardSessions.compactMap(\.card).map { SubagentLink(session: child, card: $0) } }
    }

    /// 「~/dev/ledger · feat/ocr-mapping」
    private var place: String {
        [session.cwd, session.gitBranch ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
