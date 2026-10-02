import SwiftUI
import WaypointKit

/// 고른 출처의 내용: 위에 경로·사실·읽기/항목 한 줄, 아래 본문.
/// 읽기는 Markdown이면 지침 문서 읽기 화면, 명령 규칙은 원문, Codex 기억은 항목 목록.
/// 항목은 나눈 항목 목록(프로젝트 안 지침 파일만 고치기·지우기).
struct GuidanceSourceDetail: View {
    let source: GuidanceSource
    @State private var content: Content = .loading
    @State private var showsItems = GuideLaunch.items

    enum Content: Equatable {
        case loading
        case text(String)
        case codex(CodexMemoryStore.State)
        case unreadable
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.divider)
            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // 크기·수정 시각이 바뀌면(파일 변경) 다시 읽는다.
        .task(id: source) { await load() }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: Theme.Spacing.m) {
                Text(GuideFormat.displayPath(source.path))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.Spacing.m)
                Text(facts(now: timeline.date))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .fixedSize()
                if GuidanceDocumentFormat(kind: source.kind) != nil {
                    Picker("보기", selection: $showsItems) {
                        Text("읽기").tag(false)
                        Text("항목").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Spacing.pageH)
            .frame(height: Theme.Size.rowHeight)
            .background(Theme.bgPanel)
        }
    }

    private func facts(now: Date) -> String {
        let base = GuidanceFormat.facts(source)
        guard let modified = source.modifiedAt else { return base }
        return "\(base) · \(TimeFormat.relative(modified, now: now))"
    }

    @ViewBuilder private var bodyView: some View {
        switch content {
        case .loading:
            Color.clear
        case .unreadable, .codex(.unreadable), .codex(.missing):
            Text("읽을 수 없음")
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
                .padding(Theme.Spacing.pageH)
        case .codex(.entries(let total, let recent)):
            CodexMemoryEntries(total: total, entries: recent)
        case .text(let text):
            if showsItems, let format = GuidanceDocumentFormat(kind: source.kind) {
                GuidanceSourceItems(source: source, text: text, format: format)
            } else if source.path.lowercased().hasSuffix(".md") {
                GuidanceMarkdown(content: text)
            } else {
                GuidanceRawText(text: text)
            }
        }
    }

    private func load() async {
        let source = source
        let loaded: Content = await Task.detached(priority: .userInitiated) {
            if source.kind == .codexMemory { return .codex(CodexMemoryStore.read(path: source.path)) }
            return GuidanceText.load(source.path).map(Content.text) ?? .unreadable
        }.value
        content = loaded
    }
}

/// 원문(명령 규칙 등): 모노, 줄 바꿈 없이 가로로 넘긴다.
struct GuidanceRawText: View {
    let text: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(Theme.Guide.source)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.pageH)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
