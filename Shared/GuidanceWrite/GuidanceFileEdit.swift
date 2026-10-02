import Foundation

/// 프로젝트 밖 지침 파일의 항목 고치기·지우기를 `GuidanceFileWrite.Change`로 만든다(쓰기는 `GuidanceFileWrite.apply`).
/// `base`는 화면이 항목을 나눈 원문(파일에서 그대로 읽은 것)이다.
public enum GuidanceFileEdit {

    /// 지울 수 있는 문서인가. 기억 파일은 파일 하나가 한 항목이라 늘 지울 수 있고(파일을 지운다),
    /// 나머지는 항목으로 나뉜 문서만(`GuideItemEdit.canDelete`).
    public static func canDelete(_ document: GuidanceDocument) -> Bool {
        document.format == .memory ? document.isEditable : GuideItemEdit.canDelete(document)
    }

    /// 항목 글을 바꾼 파일 내용.
    public static func replacing(path: String, base: String, format: GuidanceDocumentFormat,
                                 item: GuidanceItem, with text: String) throws -> GuidanceFileWrite.Change {
        let after = try GuideItemEdit.replacing(base, format: format, item: item, with: text)
        return GuidanceFileWrite.Change(path: path, before: base, after: after)
    }

    /// 항목(하위 포함)을 지운 바뀜. 기억 파일이면 파일을 지우고 같은 폴더 `MEMORY.md`의 색인 줄도 지운다.
    public static func removing(path: String, base: String, format: GuidanceDocumentFormat,
                                item: GuidanceItem) throws -> GuidanceFileWrite.ChangeSet {
        if format == .memory {
            let document = GuidanceDocument.parse(base, format: format)
            let found = try GuideItemEdit.locate(item, in: document)
            return try removingMemory(path: path, base: base, preview: GuideItemEdit.preview(found))
        }
        let removal = try GuideItemEdit.removing(base, format: format, item: item)
        return GuidanceFileWrite.ChangeSet(
            changes: [GuidanceFileWrite.Change(path: path, before: base, after: removal.after)],
            preview: removal.preview, childCount: removal.childCount
        )
    }

    /// 기억 파일 지우기: 파일(→ 없음) + 색인 줄. 색인이 없거나, 가리키는 줄이 없거나, 색인이 항목으로 나뉘지 않으면 파일만.
    public static func removingMemory(path: String, base: String, preview: String) throws -> GuidanceFileWrite.ChangeSet {
        var changes = [GuidanceFileWrite.Change(path: path, before: base, after: nil)]
        let name = (path as NSString).lastPathComponent
        let indexPath = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent("MEMORY.md")
        var removed = 0
        if indexPath != path, case .present(let index, _) = try GuideFile.read(URL(fileURLWithPath: indexPath)) {
            let cleaned = removingIndexLines(index, pointingTo: name)
            if cleaned.count > 0 {
                changes.append(GuidanceFileWrite.Change(path: indexPath, before: index, after: cleaned.content))
                removed = cleaned.count
            }
        }
        return GuidanceFileWrite.ChangeSet(changes: changes, preview: preview, indexLines: removed)
    }

    /// `MEMORY.md`에서 `fileName`을 가리키는 색인 줄을 모두 지운 내용과 지운 줄 수.
    /// 색인이 항목으로 나뉘지 않으면(애매) 손대지 않는다.
    public static func removingIndexLines(_ index: String, pointingTo fileName: String) -> (content: String, count: Int) {
        var content = index
        var count = 0
        while true {
            let document = GuidanceDocument.parse(content, format: .memoryIndex)
            guard document.isEditable, !document.isAmbiguous,
                  let entry = document.items.first(where: {
                      $0.kind == .indexEntry && MemoryIndexPairing.fileName($0.link ?? "") == fileName
                  }),
                  let next = try? document.delete(entry)
            else { break }
            content = next
            count += 1
        }
        return (content, count)
    }
}
