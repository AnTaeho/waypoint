import SwiftUI
import WaypointKit

/// 지침 문서 화면의 「이 프로젝트에 걸린 지침」: 전역·상위 폴더·프로젝트 파일 줄과 기억 폴더 줄(파일 수).
/// 지침 문서로 등록된 파일은 오른쪽에 「등록됨」.
struct GuidanceAppliedList: View {
    let project: Project
    @Environment(AppServices.self) private var services: AppServices?

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("없음")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
            }
            ForEach(rows, id: \.id) { row in
                HStack(spacing: Theme.Spacing.s) {
                    Text(row.title)
                        .font(Theme.Guidance.rowTitle)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(row.note)
                        .font(Theme.caption)
                        .foregroundStyle(row.registered ? Theme.done : Theme.textMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(height: Theme.Guidance.appliedRowHeight)
                .help(row.help)
                Divider().overlay(Theme.divider)
            }
        }
    }

    private struct Row {
        var id: String
        var title: String
        var note: String
        var registered: Bool
        var help: String
    }

    private var rows: [Row] {
        let sources = services?.guidance?.snapshot.applying(to: project.key) ?? []
        let fs = DiskGuidanceFileSystem()
        let root = fs.resolve((project.rootPath as NSString).expandingTildeInPath)
        let registered = Set((project.guideDocs ?? []).compactMap {
            GuidePaths.fileURL(rootPath: project.rootPath, relPath: $0.relPath).map { fs.resolve($0.path) }
        })
        var result: [Row] = []
        for source in sources where !source.isMemory {
            let isRegistered = registered.contains(source.path)
            let note = isRegistered ? "등록됨" : "\(GuidanceFormat.toolName(source.tool)) · \(GuidanceFormat.kindName(source.kind))"
            result.append(Row(id: source.path, title: GuidanceFormat.title(source, base: root), note: note,
                              registered: isRegistered, help: GuideFormat.displayPath(source.path)))
        }
        // 기억은 폴더마다 한 줄
        var folders: [String: [GuidanceSource]] = [:]
        for source in sources where source.isMemory { folders[source.memoryFolder ?? "", default: []].append(source) }
        for (name, files) in folders.sorted(by: { $0.key < $1.key }) {
            let place = files.first.map { scopeName($0.scope) } ?? ""
            result.append(Row(id: "memory:\(name)", title: "기억 \(files.count)", note: place, registered: false,
                              help: GuideFormat.displayPath((files[0].path as NSString).deletingLastPathComponent)))
        }
        return result
    }

    private func scopeName(_ scope: GuidanceScope) -> String {
        switch scope {
        case .ancestor(let dir): GuideFormat.displayPath(dir)
        case .project: "이 프로젝트"
        case .global, .otherFolder: ""
        }
    }
}
