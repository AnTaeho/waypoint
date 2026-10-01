import Foundation
import Testing
@testable import WaypointKit

/// 이 Mac의 실제 지침 출처를 읽기만 해서 속성 검사를 돌린다. 내용은 저장하거나 출력하지 않는다(경로·수만).
/// 출처가 하나도 없으면 건너뛴다.
@Suite struct GuidanceRealFileTests {

    /// `~/workspace`, `~/workspace/projects`, `~/workspace/app-factory` 바로 아래 폴더를 등록 프로젝트처럼 넘긴다.
    static func projects(home: String) -> [GuidanceProject] {
        let fm = FileManager.default
        var result: [GuidanceProject] = []
        for parent in ["workspace", "workspace/projects", "workspace/app-factory"] {
            let dir = home + "/" + parent
            for name in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where !name.hasPrefix(".") {
                var isDir: ObjCBool = false
                let path = dir + "/" + name
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                result.append(GuidanceProject(key: parent + "/" + name, rootPath: path))
            }
        }
        return result
    }

    @Test func realGuidanceRoundTrips() throws {
        let home = NSHomeDirectory()
        let snapshot = GuidanceCollector.current(home: home).collect(projects: Self.projects(home: home))
        let sources = snapshot.sources
            .compactMap { source in GuidanceDocumentFormat(kind: source.kind).map { (source.path, $0) } }
            .sorted { $0.0 < $1.0 }
        guard !sources.isEmpty else { return }

        var itemCount = 0
        var ambiguous: [String] = []
        var kinds: [GuidanceDocumentFormat: Int] = [:]
        for (path, format) in sources {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            let document = GuidanceDocument.parse(data: data, format: format)
            kinds[format, default: 0] += 1
            itemCount += document.allItems.count
            if let reason = document.ambiguity { ambiguous.append("\(path) — \(reason)") }
            guard document.isEditable else { continue }
            #expect(Array(document.joined().utf8) == Array(data), "\(path)")
            let failures = GuidanceItemCheck.failures(document)
            #expect(failures.isEmpty, "\(path): \(failures.prefix(5).map(\.description))")
        }
        let summary = kinds.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" }
        print("[실제 지침] 파일 \(sources.count)개(\(summary.joined(separator: ", "))), 항목 \(itemCount)개, 애매 \(ambiguous.count)개")
        for line in ambiguous { print("[실제 지침] 애매: \(line)") }
    }
}
