import SwiftData
import SwiftUI
import WaypointKit

/// 지침 화면: 왼쪽 출처 목록(전역·상위 폴더·프로젝트·다른 폴더), 오른쪽 고른 출처의 내용(읽기만).
struct GuidanceView: View {
    let searchText: String
    @Environment(AppServices.self) private var services: AppServices?
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedPath: String?

    var body: some View {
        let snapshot = filtered(services?.guidance?.snapshot ?? .empty)
        HStack(spacing: 0) {
            GuidanceSourceList(snapshot: snapshot, projects: projects, selection: $selectedPath)
                .frame(minWidth: Theme.Guidance.listMinWidth, idealWidth: Theme.Guidance.listWidth,
                       maxWidth: Theme.Guidance.listWidth)
            Divider().overlay(Theme.divider)
            Group {
                if let source = snapshot.sources.first(where: { $0.path == selectedPath }) {
                    GuidanceSourceDetail(source: source)
                } else {
                    GuidanceEmptyDetail(loaded: services?.guidance?.loaded ?? true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("지침")
        .onAppear { services?.guidance?.refresh() }
        .onChange(of: snapshot.sources.map(\.path), initial: true) { _, paths in
            // 고른 출처가 없거나 사라지면 목록 맨 위 것
            if selectedPath == nil || !paths.contains(selectedPath ?? "") {
                selectedPath = GuidanceSections.build(snapshot, projects: projects).first?.allSources.first?.path
            }
        }
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
