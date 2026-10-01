import SwiftUI
import WaypointKit

/// Markdown 출처: 맨 앞 머리(기억 파일의 name·description 등)는 원문 그대로 위에, 본문은 지침 문서 읽기 화면으로.
struct GuidanceMarkdown: View {
    let content: String

    var body: some View {
        let parts = GuidanceText.splitHeader(content)
        VStack(spacing: 0) {
            if let header = parts.header {
                Text(header)
                    .font(Theme.Guidance.header)
                    .foregroundStyle(Theme.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.pageH + Theme.Spacing.xs)
                    .padding(.vertical, Theme.Spacing.m)
                    .background(Theme.bgSunken)
            }
            GuideReader(content: parts.body)
        }
    }
}

/// Codex 기억 항목: 「항목 N」 아래 최근 것부터 대화 ID·시각·앞부분.
struct CodexMemoryEntries: View {
    let total: Int
    let entries: [CodexMemoryStore.Entry]

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                VStack(alignment: .leading, spacing: Theme.Guidance.entrySpacing) {
                    Text(total == 0 ? "항목 없음" : "항목 \(total)")
                        .font(Theme.section)
                        .foregroundStyle(Theme.text)
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.s) {
                                Text(entry.threadID)
                                    .font(Theme.monoCaption)
                                    .foregroundStyle(Theme.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let at = entry.updatedAt {
                                    Text(TimeFormat.relative(at, now: timeline.date))
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            Text(entry.summary)
                                .font(Theme.Guide.source)
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Divider().overlay(Theme.divider)
                    }
                    if total > entries.count {
                        Text("\(total - entries.count)개 더")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: Theme.Guide.readMaxWidth, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.pageH)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
