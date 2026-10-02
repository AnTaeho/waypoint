import SwiftUI
import WaypointKit

/// 카드 상세의 인스펙터: 카드 정보, 지금 연결된 세션, 변경된 파일, 연결된 카드, 다음 세션을 위한 메모.
struct CardInspector: View {
    let card: Card
    /// 연결된 카드를 눌렀을 때 그 카드 상세를 연다.
    let open: (Card) -> Void

    var body: some View {
        ScrollView {
            LiveDataTimeline { now in
                content(now: now)
            }
        }
        .background(Theme.bgPanel)
    }

    private func content(now: Date) -> some View {
        let sessions = openSessions(now: now)
        let overlaps = sessions.isEmpty ? .empty
            : card.project.map { WorkOverlap.index(for: $0, now: now) } ?? .empty
        let files = CardHistoryFormat.changedFiles(for: card)
        let related = relatedCards
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl + 4) {
            CardInfoGrid(card: card, now: now)
            if !sessions.isEmpty {
                InspectorSection("지금 연결된 세션") {
                    ForEach(sessions, id: \.id) { session in
                        ConnectedSessionBox(session: session, now: now, overlaps: overlaps.overlaps(for: session), open: open)
                    }
                }
            }
            if !files.isEmpty {
                InspectorSection("변경된 파일") { ChangedFilesList(files: files) }
            }
            if !related.isEmpty {
                InspectorSection("연결된 카드") { RelatedCardsList(items: related, open: open) }
            }
            if let note = card.nextSessionNote, !note.isEmpty {
                NextSessionNote(text: note)
            }
        }
        .padding(.horizontal, Theme.Spacing.l + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 끝나지 않은(live·stalled) 세션의 열린 연결. 먼저 붙은 순.
    private func openSessions(now: Date) -> [Session] {
        card.openCardSessions
            .sorted { $0.attachedAt < $1.attachedAt }
            .compactMap(\.session)
            .filter { SessionRules.state(of: $0, now: now) != .ended }
    }

    /// 상위 카드 → 하위 카드(번호순). 보관된 카드는 뺀다.
    private var relatedCards: [RelatedCard] {
        var items: [RelatedCard] = []
        if let parent = card.parent, parent.status != .archived {
            items.append(RelatedCard(card: parent, relation: "상위"))
        }
        let children = (card.children ?? [])
            .filter { $0.status != .archived }
            .sorted { $0.number < $1.number }
        items += children.map { RelatedCard(card: $0, relation: "하위") }
        return items
    }
}

/// 이름표 열 + 값 열: 프로젝트, 상태, 만든 곳, 누적 작업.
private struct CardInfoGrid: View {
    let card: Card
    let now: Date

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.l) {
            GridRow {
                label("프로젝트")
                HStack(spacing: Theme.Spacing.s) {
                    Text(card.project?.name ?? "")
                    Text(card.project?.key ?? "")
                        .font(Theme.monoCaption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            GridRow {
                label("상태")
                Text(CardFormat.statusName(card.status))
                    .font(Theme.bodyStrong)
                    .foregroundStyle(card.status == .active ? Theme.liveText : Theme.text)
            }
            GridRow {
                label("만든 곳")
                Text("\(CardFormat.originName(card.origin)) · \(TimeFormat.day(card.createdAt, now: now))")
            }
            GridRow {
                label("누적 작업")
                Text(CardFormat.workTotal(BoardQuery.stats(of: card)))
            }
        }
        .font(Theme.body)
        .foregroundStyle(Theme.text)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.textMuted)
            .frame(width: Theme.Size.inspectorLabelWidth, alignment: .leading)
    }
}

/// 인스펙터 구역: 작은 제목 + 내용.
struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.inspectorSection)
                .foregroundStyle(Theme.textMuted)
            content
        }
    }
}
