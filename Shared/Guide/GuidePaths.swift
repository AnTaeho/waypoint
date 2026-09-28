import Foundation

/// 지침 문서 경로: 프로젝트 폴더 아래 상대 경로 판정과 후보 찾기.
public enum GuidePaths {

    /// 등록할 수 있는 확장자.
    public static let allowedExtensions: Set<String> = ["md", "txt"]

    /// `rootPath`(물결표 허용)를 폴더 URL로.
    public static func rootURL(_ rootPath: String) -> URL? {
        guard !rootPath.isEmpty else { return nil }
        let expanded = (rootPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// 문서 파일 URL.
    public static func fileURL(rootPath: String, relPath: String) -> URL? {
        rootURL(rootPath)?.appendingPathComponent(relPath)
    }

    /// `file`이 `root` 아래의 .md/.txt면 상대 경로, 아니면 nil. 심볼릭 링크는 풀어서 비교한다.
    public static func relativePath(of file: URL, under root: URL) -> String? {
        guard allowedExtensions.contains(file.pathExtension.lowercased()) else { return nil }
        let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let fileParts = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard fileParts.count > rootParts.count, Array(fileParts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        return fileParts.dropFirst(rootParts.count).joined(separator: "/")
    }

    /// 등록 후보: 폴더 바로 아래 `.md`, `docs/` 바로 아래 `.md`, `.claude/CLAUDE.md`. 이미 등록된 것은 뺀다.
    /// 폴더 바로 아래 것 → docs → .claude 순, 각 묶음 안은 이름순.
    public static func candidates(in root: URL, excluding registered: Set<String>) -> [String] {
        let fm = FileManager.default
        func markdown(in sub: String) -> [String] {
            let dir = sub.isEmpty ? root : root.appendingPathComponent(sub, isDirectory: true)
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return names
                .filter { $0.lowercased().hasSuffix(".md") && !$0.hasPrefix(".") }
                .filter { name in
                    var isDir: ObjCBool = false
                    return fm.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDir) && !isDir.boolValue
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { sub.isEmpty ? $0 : "\(sub)/\($0)" }
        }
        var result = markdown(in: "") + markdown(in: "docs")
        let claude = ".claude/CLAUDE.md"
        if fm.fileExists(atPath: root.appendingPathComponent(claude).path) { result.append(claude) }
        return result.filter { !registered.contains($0) }
    }
}
