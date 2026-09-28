import SwiftData
import SwiftUI
import WaypointKit

/// 등록된 문서가 없을 때: 폴더에서 찾은 후보 줄(각 줄에 추가)과 「파일 추가…」.
struct GuideEmptyView: View {
    let project: Project
    let select: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var context
    @State private var failure: String?

    var body: some View {
        let candidates = GuideAdding.candidates(for: project)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("지침 문서")
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.text)
                if !project.rootPath.isEmpty {
                    Text(GuideFormat.displayPath((project.rootPath as NSString).expandingTildeInPath))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textMuted)
                }
                VStack(spacing: 0) {
                    ForEach(candidates, id: \.self) { relPath in
                        HStack {
                            Text(relPath)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Button("추가") { add(relPath) }
                                .font(Theme.body)
                        }
                        .frame(height: Theme.Size.rowHeight)
                        Divider().overlay(Theme.divider)
                    }
                }
                .frame(maxWidth: Theme.Guide.readMaxWidth)
                Button("파일 추가…", action: pick)
                    .font(Theme.body)
                    .disabled(project.rootPath.isEmpty)
            }
            .padding(.horizontal, Theme.Spacing.pageH)
            .padding(.vertical, Theme.Spacing.pageV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("확인", role: .cancel) {}
        }
    }

    private func add(_ relPath: String) {
        if let doc = GuideAdding.register(relPath, in: project, context: context, failure: &failure) {
            select(doc.persistentModelID)
        }
    }

    private func pick() {
        if let doc = GuideAdding.pickFile(for: project, context: context, failure: &failure) {
            select(doc.persistentModelID)
        }
    }
}
