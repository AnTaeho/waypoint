import Foundation

extension ProjectDraft {
    /// 폴더 바로 아래에서 찾는 지침 문서 후보(있는 것만, 이 차례)
    public static let folderGuideCandidates = ["AGENTS.md", "CLAUDE.md", ".claude/CLAUDE.md"]

    /// 앱에서 폴더를 골라 시작하는 등록 초안. `/tracker init`(`project_init`)과 같은 확인 창에 넣는다.
    /// 이름은 폴더 이름, 키는 `ProjectKey.suggest`, 지침 문서는 폴더 바로 아래의 흔한 지침 파일. 개요·스택·카드는 비운다.
    public static func folder(_ path: String, taken: Set<String>, home: String = NSHomeDirectory(),
                              fileManager: FileManager = .default, now: Date = Date()) -> ProjectDraft {
        let root = ProjectMatcher.normalize(path, home: home)
        let name = (root as NSString).lastPathComponent
        let guides = folderGuideCandidates.filter { relative in
            var isDir: ObjCBool = false
            let full = (root as NSString).appendingPathComponent(relative)
            return fileManager.fileExists(atPath: full, isDirectory: &isDir) && !isDir.boolValue
        }
        return ProjectDraft(rootPath: root, name: name, key: ProjectKey.suggest(name: name, folder: name, taken: taken),
                            guideFiles: guides, createdAt: now)
    }
}
