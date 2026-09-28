import SwiftUI
import WaypointKit

/// 작업중 카드 한 장. live는 클레이 테두리·펄스 점·경과, stalled는 속 빈 점·「멈춤 N분」.
/// 카드 없는 세션은 제목 자리에 「카드 없음」을 흐리게 두고 누를 수 없다.
struct PhoneWorkCard: View {
    let item: PhoneWorkItem
    let now: Date

    private var row: DashboardRow { item.row }
    private var isLive: Bool { row.workState == .live }

    var body: some View {
        if let card = row.card {
            NavigationLink(value: card) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Phone.lineGap) {
            HStack(spacing: Theme.Spacing.s) {
                WorkStateDot(state: row.workState)
                Text(meta)
                    .font(Theme.Phone.meta)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                elapsed
            }
            Text(row.card?.title ?? "카드 없음")
                .font(row.card == nil ? Theme.Phone.body : Theme.Phone.cardTitle)
                .foregroundStyle(row.card == nil ? Theme.textMuted : Theme.text)
                .lineSpacing(Theme.Phone.titleLineSpacing)
                .multilineTextAlignment(.leading)
            Text(sessionLine)
                .font(Theme.Phone.meta)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Theme.Phone.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Phone.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Phone.cardRadius)
                .strokeBorder(
                    isLive ? Theme.live : Theme.border,
                    lineWidth: isLive ? Theme.Size.liveBorder : Theme.Size.cardBorder
                )
        }
        .padding(.leading, row.depth > 0 ? Theme.Phone.indent : 0)
        .contentShape(Rectangle())
    }

    /// 「LDG-14 · 가계부 앱」, 카드 없으면 프로젝트 이름만.
    private var meta: String {
        guard let card = row.card else { return item.project.name }
        return "\(card.displayID) · \(item.project.name)"
    }

    /// 「sess·7f2a · ReceiptParser.swift」
    private var sessionLine: String {
        let label = SessionFormat.label(for: row.session)
        let file = row.card.map { SessionFormat.recentFileName(card: $0, session: row.session) }
            ?? SessionFormat.recentFileName(session: row.session)
        guard let file else { return label }
        return "\(label) · \(file)"
    }

    @ViewBuilder private var elapsed: some View {
        if isLive {
            Text(TimeFormat.elapsed(from: row.session.startedAt, to: now))
                .font(Theme.Phone.elapsed)
                .foregroundStyle(Theme.liveText)
        } else {
            Text("멈춤 \(TimeFormat.elapsed(from: row.session.lastSeenAt, to: now))")
                .font(Theme.Phone.stalled)
                .foregroundStyle(Theme.textMuted)
        }
    }
}
