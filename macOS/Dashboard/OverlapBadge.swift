import SwiftUI
import WaypointKit

/// 「같은 파일 N개 · PRB-3」. 누르면 상대마다 겹친 파일 목록. 겹침이 없으면 아무것도 그리지 않는다.
struct OverlapBadge: View {
    let overlaps: [WorkOverlap.Overlap]
    @State private var showsFiles = false

    var body: some View {
        if let summary = WorkOverlap.summary(overlaps) {
            Button { showsFiles.toggle() } label: {
                Label(summary, systemImage: Theme.Overlap.icon)
                    .font(Theme.Overlap.font)
                    .foregroundStyle(Theme.Overlap.text)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(Theme.Overlap.background, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(overlaps.flatMap(\.files).joined(separator: "\n"))
            .popover(isPresented: $showsFiles, arrowEdge: .bottom) { OverlapFileList(overlaps: overlaps) }
        }
    }
}

/// 상대마다: 카드·도구·세션 한 줄, 그 아래 겹친 파일.
struct OverlapFileList: View {
    let overlaps: [WorkOverlap.Overlap]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("같은 파일 작업 중").font(Theme.inspectorSection).foregroundStyle(Theme.textMuted)
            ForEach(overlaps, id: \.other.id) { overlap in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(heading(overlap)).font(Theme.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
                    ForEach(overlap.files.prefix(Theme.Overlap.fileLimit), id: \.self) { path in
                        Text(path).font(Theme.mono).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1).truncationMode(.head).textSelection(.enabled)
                    }
                    if overlap.files.count > Theme.Overlap.fileLimit {
                        Text("외 \(overlap.files.count - Theme.Overlap.fileLimit)개")
                            .font(Theme.caption).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(width: Theme.Overlap.popoverWidth, alignment: .leading)
    }

    /// 「PRB-3 파서 · Codex sess·1a2b」, 카드가 없으면 「Claude Code sess·1a2b」.
    private func heading(_ overlap: WorkOverlap.Overlap) -> String {
        let session = "\(overlap.other.provider.name) \(SessionFormat.label(kind: .main, id: overlap.other.sourceID, agentName: nil))"
        guard let card = overlap.cards.first else { return session }
        return "\(card.displayID) \(card.title) · \(session)"
    }
}
