import SwiftUI
import WaypointKit

/// 보드 한 칸: 머리(표시·이름·개수)와 카드 목록. 받는 칸이면 카드를 끌어 놓을 수 있다.
/// 작업중 칸은 카드 아래에 카드 없는 세션 타일을 둔다(개수에 함께 센다 — 사이드바·프로젝트 표의 작업중 수와 같은 기준).
struct BoardColumnView: View {
    let column: BoardColumn
    let items: [BoardItem]
    let now: Date
    /// 작업중 칸의 카드 없는 세션. 다른 칸은 비어 있다.
    var tiles: [BoardSessionTile] = []
    /// 끌어 놓은 카드 UUID 문자열 → 옮겼으면 true
    let onDrop: (String) -> Bool

    @State private var isTargeted = false
    @State private var showsAllIdeas = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(shownItems) { item in
                        NavigationLink(value: item.card) {
                            BoardCardView(card: item.card, column: column, now: now)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, item.depth > 0 ? Theme.Spacing.indent : 0)
                        .draggable(item.card.id.uuidString)
                    }
                    ForEach(tiles) { tile in
                        BoardSessionTileView(tile: tile, now: now)
                    }
                    if column == .idea, items.count > Theme.Board.ideaPreviewCount {
                        moreButton
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, Theme.Board.columnPaddingH)
        .padding(.vertical, Theme.Board.columnPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .fill(column == .active ? Theme.liveColumn : Theme.bgSunken)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .strokeBorder(Theme.liveText, lineWidth: Theme.Size.liveBorder)
            }
        }
        .modifier(DropTarget(enabled: column.acceptsDrop, isTargeted: $isTargeted, onDrop: onDrop))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            marker
            Text(title)
                .font(Theme.section)
                .foregroundStyle(column == .active ? Theme.liveText : Theme.text)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text("\(items.count + tiles.count)")
                .font(Theme.captionLarge)
                .foregroundStyle(column == .active ? Theme.liveText : Theme.textMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xxs)
    }

    @ViewBuilder private var marker: some View {
        switch column {
        case .idea:
            Image(systemName: "lightbulb").font(Theme.body).foregroundStyle(Theme.text)
        case .next:
            FilledDot(color: Theme.next)
        case .active:
            if items.isEmpty && tiles.isEmpty { FilledDot(color: Theme.live) } else { LiveDot() }
        case .done:
            Image(systemName: "checkmark").font(Theme.bodyStrong).foregroundStyle(Theme.done)
        }
    }

    private var title: String {
        switch column {
        case .idea: "아이디어 · 나중에"
        case .next: "다음 할 일"
        case .active: "작업중"
        case .done: "완료 · 최근 7일"
        }
    }

    // MARK: 아이디어 칸 접기

    private var previewLimit: Int? {
        column == .idea && !showsAllIdeas ? Theme.Board.ideaPreviewCount : nil
    }

    private var shownItems: [BoardItem] {
        guard let previewLimit else { return items }
        return Array(items.prefix(previewLimit))
    }

    private var hiddenCount: Int { items.count - shownItems.count }

    private var moreButton: some View {
        Button(showsAllIdeas ? "접기" : "\(hiddenCount)개 더 보기") {
            showsAllIdeas.toggle()
        }
        .buttonStyle(.plain)
        .font(Theme.body)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs + 2)
    }
}

/// 받는 칸에만 드롭 대상을 단다. 작업중 칸은 드래그 중에도 강조되지 않는다.
private struct DropTarget: ViewModifier {
    let enabled: Bool
    @Binding var isTargeted: Bool
    let onDrop: (String) -> Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                return onDrop(id)
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        } else {
            content
        }
    }
}
