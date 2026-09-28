import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WaypointKit

/// 문서 추가 메뉴(+): 폴더에서 찾은 후보 + 「파일 추가…」.
struct GuideAddMenu: View {
    let project: Project
    let select: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var context
    @State private var failure: String?

    var body: some View {
        Menu {
            let candidates = GuideAdding.candidates(for: project)
            ForEach(candidates, id: \.self) { relPath in
                Button(relPath) { add(relPath) }
            }
            if !candidates.isEmpty { Divider() }
            Button("파일 추가…", action: pick)
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, Theme.Spacing.s)
        .help("문서 추가")
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

/// 등록 동작(메뉴와 빈 화면이 함께 쓴다).
@MainActor
enum GuideAdding {
    static func candidates(for project: Project) -> [String] {
        guard let root = GuidePaths.rootURL(project.rootPath) else { return [] }
        return GuidePaths.candidates(in: root, excluding: Set((project.guideDocs ?? []).map(\.relPath)))
    }

    static func register(_ relPath: String, in project: Project, context: ModelContext, failure: inout String?) -> GuideDoc? {
        do {
            return try GuideLibrary.register(relPath, in: project, at: Date(), context: context)
        } catch GuideLibrary.Failure.alreadyRegistered {
            failure = "이미 있는 문서"
        } catch {
            failure = "추가 못 함 · \(relPath)"
        }
        return nil
    }

    /// 프로젝트 폴더에서 시작하는 열기 창. 폴더 밖이나 .md·.txt가 아닌 파일은 받지 않는다.
    static func pickFile(for project: Project, context: ModelContext, failure: inout String?) -> GuideDoc? {
        guard let root = GuidePaths.rootURL(project.rootPath) else { return nil }
        let panel = NSOpenPanel()
        panel.directoryURL = root
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md"), .plainText].compactMap { $0 }
        panel.prompt = "추가"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let relPath = GuidePaths.relativePath(of: url, under: root) else {
            failure = "프로젝트 폴더 밖의 파일"
            return nil
        }
        return register(relPath, in: project, context: context, failure: &failure)
    }
}
