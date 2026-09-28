import SwiftData
import SwiftUI
import WaypointKit

/// 지침 문서 화면: 위에 문서 줄(이름·상태·읽기/편집), 아래 본문(읽기·편집·충돌 비교).
struct GuideView: View {
    let project: Project
    @Binding var selectedID: PersistentIdentifier?

    @State private var mode: GuideMode = .read

    var body: some View {
        let docs = (project.guideDocs ?? []).sorted { $0.relPath.localizedStandardCompare($1.relPath) == .orderedAscending }
        let doc = docs.first { $0.persistentModelID == selectedID } ?? docs.first
        VStack(spacing: 0) {
            if let doc {
                GuideHeaderBar(project: project, docs: docs, current: doc, mode: $mode) { selectedID = $0 }
                Divider().overlay(Theme.divider)
                content(doc)
            } else {
                GuideEmptyView(project: project) { selectedID = $0 }
            }
        }
        .background(Theme.bg)
        .navigationTitle(project.name)
        .onChange(of: doc?.persistentModelID) { _, id in
            if selectedID != id { selectedID = id }
            // 저장 안 한 편집이 있는 문서로 오면 편집으로
            mode = doc?.draft != nil ? .edit : .read
        }
        .onAppear {
            if selectedID != doc?.persistentModelID { selectedID = doc?.persistentModelID }
            if doc?.draft != nil { mode = .edit }
        }
    }

    @ViewBuilder private func content(_ doc: GuideDoc) -> some View {
        if let local = doc.conflictContent {
            GuideConflictView(doc: doc, local: local) { mode = .read }
        } else {
            switch mode {
            case .read: GuideReader(content: doc.content)
            case .edit: GuideEditor(doc: doc) { mode = .read }
            }
        }
    }
}

enum GuideMode: Hashable {
    case read, edit
}
