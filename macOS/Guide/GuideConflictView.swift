import SwiftData
import SwiftUI
import WaypointKit

/// 충돌 비교: 왼쪽 로컬 파일, 오른쪽 앱에서 편집한 내용. 한쪽에만 있는 줄은 배경으로 표시한다.
struct GuideConflictView: View {
    let doc: GuideDoc
    let local: String
    /// 한쪽을 골라 충돌이 풀렸을 때(읽기로 돌아간다)
    let resolved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var error: String?

    var body: some View {
        let app = doc.draft ?? doc.content
        let lines = LineDiff.diff(local, app)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Text("충돌")
                    .font(Theme.sectionLarge)
                    .foregroundStyle(Theme.liveText)
                if let error {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.liveText)
                }
                Spacer()
                Button("로컬 파일로", action: keepLocal)
                Button("앱 내용으로", action: keepApp)
            }
            .font(Theme.body)
            GeometryReader { proxy in
                HStack(spacing: Theme.Spacing.m) {
                    ConflictColumn(
                        title: "로컬 파일",
                        lines: lines.filter { $0.kind != .added },
                        highlight: .removed
                    )
                    ConflictColumn(
                        title: "앱에서 편집한 내용",
                        lines: lines.filter { $0.kind != .removed },
                        highlight: .added
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .padding(.horizontal, Theme.Spacing.pageH)
        .padding(.vertical, Theme.Spacing.l)
    }

    private func keepLocal() {
        do {
            try GuideLibrary.keepLocal(doc, at: Date(), context: context)
            resolved()
        } catch { self.error = error.localizedDescription }
    }

    private func keepApp() {
        do {
            try GuideLibrary.keepApp(doc, at: Date(), context: context)
            resolved()
        } catch { self.error = error.localizedDescription }
    }
}

/// 한쪽 원문. 반대쪽에 없는 줄에 배경을 깐다.
private struct ConflictColumn: View {
    let title: String
    let lines: [LineDiff.Line]
    let highlight: LineDiff.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.tableHeader)
                .foregroundStyle(Theme.textMuted)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(Theme.Guide.source)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Guide.diffLinePadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(line.kind == highlight ? background : Color.clear)
                    }
                }
                .textSelection(.enabled)
                .padding(.vertical, Theme.Spacing.s)
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var background: Color {
        highlight == .removed ? Theme.Guide.removedLine : Theme.Guide.addedLine
    }
}
