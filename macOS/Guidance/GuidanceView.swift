import SwiftData
import SwiftUI
import WaypointKit

/// 지침 화면: 왼쪽 출처 목록(전역·상위 폴더·프로젝트·다른 폴더·지운 파일), 오른쪽 고른 출처의 내용.
/// 프로젝트 밖 파일 쓰기에 쓰는 것(백업 자리·Codex·지움 알림)을 여기서 아래로 내려 준다.
struct GuidanceView: View {
    let searchText: String
    @Environment(AppServices.self) private var services: AppServices?
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedPath: String?
    /// 사본만 남은 경로
    @State private var deleted: [String] = []
    @State private var toast: FileToast?
    @State private var backups = try? GuidanceBackupStore.appDefault()
    @State private var codex = CommandRulesCheck.findCodex()

    struct FileToast: Identifiable {
        let id = UUID()
        var message: String
        /// nil이면 되돌리기 없이 알림만
        var removal: GuidanceFileWrite.ChangeSet?
    }

    var body: some View {
        let snapshot = filtered(services?.guidance?.snapshot ?? .empty)
        HStack(spacing: 0) {
            GuidanceSourceList(snapshot: snapshot, projects: projects, deleted: deleted, selection: $selectedPath)
                .frame(minWidth: Theme.Guidance.listMinWidth, idealWidth: Theme.Guidance.listWidth,
                       maxWidth: Theme.Guidance.listWidth)
            Divider().overlay(Theme.divider)
            Group {
                if let source = snapshot.sources.first(where: { $0.path == selectedPath }) {
                    GuidanceSourceDetail(source: source)
                } else if let path = selectedPath, deleted.contains(path) {
                    GuidanceDeletedDetail(path: path)
                } else {
                    GuidanceEmptyDetail(loaded: services?.guidance?.loaded ?? true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            if let toast {
                GuidanceUndoToast(message: toast.message, undo: toast.removal.map { removal in { undo(removal) } })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: toast?.id)
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.GuideItems.toastSeconds))
            if !Task.isCancelled { toast = nil }
        }
        .environment(\.guidanceFiles, fileContext)
        .navigationTitle("지침")
        .onAppear { services?.guidance?.refresh() }
        .onChange(of: snapshot.sources.map(\.path), initial: true) { _, paths in
            deleted = deletedPaths()
            // 고른 출처가 없거나 사라지면 목록 맨 위 것(지운 파일로 남았으면 그대로)
            let path = selectedPath ?? ""
            if selectedPath == nil, let suffix = GuideLaunch.guidanceSource,
               let found = (paths + deleted).first(where: { $0.hasSuffix(suffix) }) {
                selectedPath = found
            } else if selectedPath == nil || !(paths.contains(path) || deleted.contains(path)) {
                selectedPath = GuidanceSections.build(snapshot, projects: projects).first?.allSources.first?.path
            }
        }
    }

    private var fileContext: GuidanceFileContext {
        GuidanceFileContext(
            backups: backups, codex: codex,
            didWrite: { [services] in services?.guidance?.refresh() },
            showUndo: { removal in toast = FileToast(message: removal.summary, removal: removal) }
        )
    }

    /// 지운 것을 되살린다(먼저 모두 지운 직후와 같은지 확인, 아니면 쓰지 않는다).
    private func undo(_ removal: GuidanceFileWrite.ChangeSet) {
        toast = nil
        let context = fileContext
        Task { @MainActor in
            do {
                try await GuidanceFileRunner.apply(removal.inverted.changes, context: context, reason: .undo, checkRules: false)
            } catch {
                toast = FileToast(message: "되돌리지 못함 · \(GuidanceFileRunner.message(error))")
            }
            context.didWrite()
        }
    }

    private func deletedPaths() -> [String] {
        (backups?.backedUpPaths() ?? []).filter { !FileManager.default.fileExists(atPath: $0) }
    }

    /// 검색어가 경로에 들어간 출처만.
    private func filtered(_ snapshot: GuidanceSnapshot) -> GuidanceSnapshot {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return snapshot }
        var result = snapshot
        result.sources = snapshot.sources.filter {
            $0.path.localizedCaseInsensitiveContains(query) || GuidanceFormat.kindName($0.kind).contains(query)
        }
        return result
    }
}

/// 보일 출처가 없을 때.
private struct GuidanceEmptyDetail: View {
    let loaded: Bool

    var body: some View {
        Text(loaded ? "찾은 지침 없음" : "")
            .font(Theme.body)
            .foregroundStyle(Theme.textMuted)
    }
}
