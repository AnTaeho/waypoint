import SwiftUI
import WaypointKit

/// 항목 한 줄. 마우스를 올리면 흰 바탕 + 옅은 그림자, 오른쪽에 고치기·지우기.
struct GuidanceItemRow: View {
    let item: GuidanceItem
    /// nil이면 버튼 없음
    let edit: (() -> Void)?
    let delete: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            GuidanceItemText(item: item)
                .frame(maxWidth: .infinity, alignment: .leading)
            if edit != nil || delete != nil {
                // 자리는 늘 잡아 두고 올렸을 때만 보인다(글이 다시 흐르지 않게)
                buttons
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
            }
        }
        .padding(.horizontal, Theme.GuideItems.rowPaddingH)
        .padding(.vertical, Theme.GuideItems.rowPaddingV)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: Theme.Radius.row)
                    .fill(Theme.GuideItems.hoverBg)
                    .shadow(color: Theme.GuideItems.hoverShadow, radius: Theme.GuideItems.hoverShadowRadius,
                            y: Theme.GuideItems.hoverShadowY)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 && (edit != nil || delete != nil) }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if let edit {
                iconButton("pencil", label: "고치기", color: Theme.textMuted, action: edit)
            }
            if let delete {
                iconButton("trash", label: "지우기", color: Theme.liveText, action: delete)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Theme.GuideItems.iconSize))
                .foregroundStyle(color)
                .frame(width: Theme.GuideItems.buttonSize, height: Theme.GuideItems.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 항목 글. 절 머리는 작은 굵은 회색, 코드·표·머리는 원문 일부를 모노로, 나머지는 인라인 Markdown.
struct GuidanceItemText: View {
    let item: GuidanceItem

    var body: some View {
        switch item.kind {
        case .heading:
            Text(MarkdownInline.text(item.display, size: Theme.GuideItems.headingSize, bold: true))
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
        case .document:
            // 나누지 않은 문서는 한 덩어리 원문 그대로
            Text(item.text)
                .font(Theme.Guide.code)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .code, .tableHeader, .tableRow, .frontmatter, .rule:
            Text(sourceLines)
                .font(Theme.Guide.code)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(Theme.GuideItems.sourceLineLimit + 1)
        default:
            Text(MarkdownInline.text(prefix + item.display))
                .foregroundStyle(Theme.text)
                .lineSpacing(Theme.Guide.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 번호 목록은 번호를 앞에 둔다.
    private var prefix: String {
        item.kind == .numbered ? (item.marker.map { $0 + " " } ?? "") : ""
    }

    private var sourceLines: String {
        let lines = item.text.split(separator: "\n", omittingEmptySubsequences: false)
        let shown = lines.prefix(Theme.GuideItems.sourceLineLimit).joined(separator: "\n")
        return lines.count > Theme.GuideItems.sourceLineLimit ? shown + "\n…" : shown
    }
}
