import SwiftUI
import WaypointKit

/// Markdown 블록 하나.
struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownInline.text(text, size: headingSize(level), bold: true))
                .foregroundStyle(Theme.text)
                .padding(.top, level <= 2 ? Theme.Spacing.m : Theme.Spacing.xs)
        case .paragraph(let text):
            Text(MarkdownInline.text(text))
                .foregroundStyle(Theme.text)
                .lineSpacing(3)
        case .list(let items):
            MarkdownListView(items: items)
        case .code(_, let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(Theme.Guide.code)
                    .foregroundStyle(Theme.text)
                    .padding(Theme.Spacing.m + 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgSunken, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        case .table(let table):
            MarkdownTableView(table: table)
        case .quote(let text):
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: Theme.Guide.quoteBar)
                Text(MarkdownInline.text(text))
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: Theme.Guide.h1Size
        case 2: Theme.Guide.h2Size
        default: Theme.Guide.h3Size
        }
    }
}

/// 목록: 점·번호·체크 상자 + 본문, 들여쓰기 단계만큼 안으로.
private struct MarkdownListView: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs + 1) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    marker(item)
                        .frame(minWidth: Theme.Spacing.l, alignment: .trailing)
                    Text(MarkdownInline.text(item.text))
                        .foregroundStyle(item.checked == true ? Theme.textMuted : Theme.text)
                        .lineSpacing(3)
                }
                .padding(.leading, CGFloat(item.depth) * Theme.Spacing.xl)
            }
        }
    }

    @ViewBuilder private func marker(_ item: MarkdownListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square" : "square")
                .font(Theme.caption)
                .foregroundStyle(checked ? Theme.done : Theme.textMuted)
        } else if case .number(let n) = item.marker {
            Text("\(n).")
                .font(Theme.Guide.body)
                .foregroundStyle(Theme.textMuted)
        } else {
            Text("•")
                .font(Theme.Guide.body)
                .foregroundStyle(Theme.textMuted)
        }
    }
}

/// 표: 머리 줄 굵게, 칸 사이 구분선. 넓으면 가로로 넘긴다.
private struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                row(table.header, header: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                    Divider().overlay(Theme.divider)
                    row(cells, header: false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.row)
                    .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(MarkdownInline.text(cell, size: Theme.Guide.bodySize - 0.5, bold: header))
                    .foregroundStyle(header ? Theme.textSecondary : Theme.text)
                    .frame(minWidth: Theme.Guide.tableCellMinWidth, alignment: frameAlignment(index))
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    // 칸이 열 폭을 다 채워야 머리 줄 배경이 끊기지 않는다
                    .frame(maxWidth: .infinity, alignment: frameAlignment(index))
                    .background(header ? Theme.bgPanel : Color.clear)
                    .gridColumnAlignment(columnAlignment(index))
            }
        }
    }

    private func columnAlignment(_ index: Int) -> HorizontalAlignment {
        switch index < table.alignments.count ? table.alignments[index] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ index: Int) -> Alignment {
        switch index < table.alignments.count ? table.alignments[index] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
