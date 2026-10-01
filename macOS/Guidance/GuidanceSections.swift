import Foundation
import WaypointKit

/// 출처 목록의 묶음 하나: 이름, 파일 줄들, 기억 폴더(접을 수 있게).
struct GuidanceSection: Identifiable {
    struct MemoryGroup: Identifiable {
        var id: String
        var title: String
        var sources: [GuidanceSource]
    }

    var id: String
    var title: String
    var subtitle: String?
    /// 줄 이름을 이 폴더 기준 상대 경로로
    var base: String?
    var files: [GuidanceSource]
    var memory: [MemoryGroup]

    var allSources: [GuidanceSource] { files + memory.flatMap(\.sources) }
}

/// 수집 결과를 화면 묶음으로: 전역 → 상위 폴더 → 프로젝트(이름순) → 다른 폴더.
enum GuidanceSections {

    static func build(_ snapshot: GuidanceSnapshot, projects: [Project], home: String = NSHomeDirectory()) -> [GuidanceSection] {
        var sections: [GuidanceSection] = []
        let global = snapshot.sources(in: .global)
            .sorted { ($0.tool == .claude ? 0 : 1, $0.path) < ($1.tool == .claude ? 0 : 1, $1.path) }
        if !global.isEmpty {
            sections.append(GuidanceSection(id: "global", title: "전역", files: global, memory: []))
        }
        for dir in snapshot.ancestors {
            let sources = snapshot.sources(in: .ancestor(dir))
            guard !sources.isEmpty else { continue }
            sections.append(section(id: "ancestor:\(dir)", title: GuideFormat.displayPath(dir, home: home),
                                    subtitle: nil, base: dir, sources: sources))
        }
        for project in projects {
            let sources = snapshot.sources(in: .project(project.key))
            guard !sources.isEmpty else { continue }
            let root = DiskGuidanceFileSystem().resolve((project.rootPath as NSString).expandingTildeInPath)
            sections.append(section(id: "project:\(project.key)", title: project.name, subtitle: project.key,
                                    base: root, sources: sources))
        }
        let others = snapshot.memoryFolders.compactMap { folder -> GuidanceSection.MemoryGroup? in
            guard case .other(let path, let onDisk) = folder.match else { return nil }
            let sources = ordered(snapshot.sources(in: .otherFolder(folder.name)))
            guard !sources.isEmpty else { return nil }
            return .init(id: folder.name, title: GuidanceFormat.otherFolderTitle(path: path, onDisk: onDisk, home: home),
                         sources: sources)
        }
        if !others.isEmpty {
            sections.append(GuidanceSection(id: "other", title: "다른 폴더", files: [], memory: others))
        }
        return sections
    }

    private static func section(id: String, title: String, subtitle: String?, base: String,
                                sources: [GuidanceSource]) -> GuidanceSection {
        let files = sources.filter { !$0.isMemory }.sorted { $0.path < $1.path }
        let memory = ordered(sources.filter(\.isMemory))
        let groups = memory.isEmpty ? [] : [GuidanceSection.MemoryGroup(id: id + ":memory", title: "기억 \(memory.count)", sources: memory)]
        return GuidanceSection(id: id, title: title, subtitle: subtitle, base: base, files: files, memory: groups)
    }

    /// 기억 목록(MEMORY.md) 먼저, 나머지는 이름순.
    private static func ordered(_ sources: [GuidanceSource]) -> [GuidanceSource] {
        sources.sorted { ($0.kind == .memoryIndex ? 0 : 1, $0.path) < ($1.kind == .memoryIndex ? 0 : 1, $1.path) }
    }
}
