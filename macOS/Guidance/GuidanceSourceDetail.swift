import SwiftData
import SwiftUI
import WaypointKit

/// 고른 출처의 내용: 위에 경로·사실·읽기/항목 한 줄, 아래 본문.
/// 읽기는 Markdown이면 지침 문서 읽기 화면, 명령 규칙은 원문, Codex 기억은 항목 목록.
/// 항목은 나눈 항목 목록(프로젝트 안 지침 파일은 지침 문서로, 프로젝트 밖 파일은 파일 그대로 고치기·지우기).
struct GuidanceSourceDetail: View {
    let source: GuidanceSource
    @Environment(\.guidanceFiles) private var files
    @Query(filter: #Predicate<Session> { $0.endedAt == nil }) private var openSessions: [Session]
    @State private var content: Content = .loading
    @State private var showsItems = GuideLaunch.items
    @State private var backups: [GuidanceBackupStore.Backup] = []
    @State private var showsBackups = false

    enum Content: Equatable {
        case loading
        case text(String)
        case codex(CodexMemoryStore.State)
        case unreadable
    }

    var body: some View {
        VStack(spacing: 0) {
            GuidanceSourceHeader(
                source: source, showsItems: $showsItems, notes: notes, backupCount: backups.count,
                openBackups: { showsBackups = true }
            )
            Divider().overlay(Theme.divider)
            bodyView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // 크기·수정 시각이 바뀌면(파일 변경) 다시 읽는다.
        .task(id: source) { await load() }
        .sheet(isPresented: $showsBackups) {
            GuidanceBackupSheet(path: source.path, backups: backups)
        }
    }

    /// 경로 오른쪽 사실 앞에 붙일 짧은 사실: 이 파일을 읽는 열린 세션 수, 규칙 검사를 Codex 없이 하는지.
    private var notes: [String] {
        guard GuidanceFileWrite.isWritable(kind: source.kind, path: source.path) else { return [] }
        var notes: [String] = []
        if let sessions = GuidanceOpenSessions.label(
            for: source, count: GuidanceOpenSessions.count(for: source, sessions: openSessions)) {
            notes.append(sessions)
        }
        if source.kind == .commandRules && files.codex == nil { notes.append("codex 없음 · 간단 검사") }
        return notes
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
        let store = GuidanceFileWrite.isWritable(kind: source.kind, path: source.path) ? files.backups : nil
        let loaded: (Content, [GuidanceBackupStore.Backup]) = await Task.detached(priority: .userInitiated) {
            let list = store?.backups(of: source.path) ?? []
            if source.kind == .codexMemory { return (.codex(CodexMemoryStore.read(path: source.path)), list) }
            return (GuidanceText.load(source.path).map(Content.text) ?? .unreadable, list)
        }.value
        content = loaded.0
        backups = loaded.1
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
