import SwiftUI
import WaypointKit

struct ProjectTableItem: Identifiable {
    let project: Project
    let summary: ProjectSummary
    var id: UUID { project.id }
}

/// 프로젝트 표. 줄을 누르면 사이드바 선택이 그 프로젝트로 바뀐다.
struct ProjectTable: View {
    let items: [ProjectTableItem]
    let now: Date
    let select: (Project) -> Void
    @State private var width: CGFloat = 0

    var body: some View {
        let columns = TableWidth.project(tableWidth: width)
        VStack(alignment: .leading, spacing: 0) {
            Text("프로젝트")
                .font(Theme.section)
                .foregroundStyle(Theme.text)
                .padding(.bottom, Theme.Spacing.s + 1)
            TableHeader {
                Text("이름").frame(maxWidth: .infinity, alignment: .leading)
                if let folder = columns.folder {
                    Text("폴더").frame(width: folder, alignment: .leading)
                }
                Text("작업중").frame(width: columns.count, alignment: .trailing)
                Text("다음").frame(width: columns.count, alignment: .trailing)
                Text("아이디어").frame(width: columns.count, alignment: .trailing)
                Text("마지막 활동").frame(width: Theme.Columns.projectActivity, alignment: .trailing)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    select(item.project)
                } label: {
                    ProjectTableRow(
                        item: item, now: now, columns: columns, showsDivider: index < items.count - 1
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .readWidth(into: $width)
    }
}

private struct ProjectTableRow: View {
    let item: ProjectTableItem
    let now: Date
    let columns: ProjectColumns
    let showsDivider: Bool

    var body: some View {
        let summary = item.summary
        HStack(spacing: Theme.Spacing.l) {
            Text(item.project.name)
                .font(Theme.bodyMedium)
                .foregroundStyle(summary.liveCount > 0 ? Theme.text : Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let folder = columns.folder {
                Text(item.project.rootPath)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: folder, alignment: .leading)
            }
            Group {
                if summary.liveCount > 0 {
                    Text("\(summary.liveCount)").font(Theme.bodyStrong).foregroundStyle(Theme.liveText)
                } else {
                    Text("–").font(Theme.body).foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: columns.count, alignment: .trailing)
            count(summary.nextCount)
            count(summary.ideaCount)
            Text(summary.lastActivityAt.map { TimeFormat.relative($0, now: now) } ?? "–")
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .frame(width: Theme.Columns.projectActivity, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, Theme.Spacing.rowH)
        .frame(height: Theme.Size.projectRowHeight)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private func count(_ n: Int) -> some View {
        Text("\(n)")
            .font(Theme.body)
            .foregroundStyle(Theme.text)
            .frame(width: columns.count, alignment: .trailing)
    }
}
