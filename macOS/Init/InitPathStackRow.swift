import SwiftUI
import WaypointKit

/// 경로(모노)와 스택 칩(빼기·더하기).
struct InitPathStackRow: View {
    let path: String
    @Binding var form: InitForm
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.l) {
                label("경로")
                Text(path)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.l) {
                label("스택")
                FlowLayout(spacing: Theme.Init.chipGap) {
                    ForEach(form.stack, id: \.self) { item in
                        chip(item)
                    }
                    TextField("추가", text: $newItem)
                        .textFieldStyle(.plain)
                        .font(Theme.body)
                        .frame(width: Theme.Init.stackInputWidth)
                        .padding(.vertical, Theme.Init.chipV)
                        .onSubmit(add)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.Init.label)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: Theme.Init.rowLabelWidth, alignment: .leading)
    }

    private func chip(_ item: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(item)
            Button {
                form.stack.removeAll { $0 == item }
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("\(item) 빼기")
        }
        .font(Theme.body)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, Theme.Init.chipH)
        .padding(.vertical, Theme.Init.chipV)
        .background(Theme.bgSunken, in: Capsule())
    }

    private func add() {
        form.addStack(newItem)
        newItem = ""
    }
}

/// 줄을 넘기며 가로로 늘어놓는 배치.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            if rows[rows.count - 1].width + extra + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
