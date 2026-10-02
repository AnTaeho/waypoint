import Foundation
import SwiftData

/// 지침 문서 항목 하나를 고치거나 지운다. 쓰기는 모두 `GuideLibrary.save`를 거쳐
/// 원자적 쓰기·`GuideVersion(app)`·`guide.synced`·충돌 판정을 그대로 쓴다.
///
/// `base`는 화면이 항목을 나눈 원문이다. 쓰기 직전에 `base`를 다시 나눠 같은 번호의 항목을 찾고
/// 글이 같을 때만 그 범위로 바꾼다. 앱 기록(`doc.content`)이 `base`와 다르면(그사이 로컬 변경이 반영됨)
/// 쓰지 않고 충돌로 멈춘다.
public enum GuideItemEdit {

    public enum Failure: Error, Equatable {
        /// 화면의 항목이 `base`에 없거나 글이 다르다
        case staleItem
        /// 항목으로 나누기 애매한 문서라 지우지 않는다
        case ambiguous
        /// UTF-8로 읽지 못한 원문
        case notEditable
    }

    /// 지운 기록. 되돌리기에 쓴다.
    public struct Removal: Equatable, Sendable {
        /// 지우기 전 문서
        public var before: String
        /// 지운 뒤 문서
        public var after: String
        /// 지운 항목 앞부분(표시용 글)
        public var preview: String
        /// 함께 지운 하위 항목 수
        public var childCount: Int

        public init(before: String, after: String, preview: String, childCount: Int) {
            self.before = before
            self.after = after
            self.preview = preview
            self.childCount = childCount
        }
    }

    /// 항목으로 지울 수 있는 문서인가. 애매한 문서(문서 전체 한 항목)는 실수로 비우지 않게 막는다.
    public static func canDelete(_ document: GuidanceDocument) -> Bool {
        document.isEditable && !document.isAmbiguous
    }

    /// `base`의 항목을 `text`로 바꾼 문서 전체.
    public static func replacing(_ base: String, format: GuidanceDocumentFormat,
                                 item: GuidanceItem, with text: String) throws -> String {
        let document = GuidanceDocument.parse(base, format: format)
        return try document.replace(try locate(item, in: document), with: text)
    }

    /// `base`에서 항목(하위 포함)을 지운 기록.
    public static func removing(_ base: String, format: GuidanceDocumentFormat,
                                item: GuidanceItem) throws -> Removal {
        let document = GuidanceDocument.parse(base, format: format)
        guard document.isEditable else { throw Failure.notEditable }
        guard canDelete(document) else { throw Failure.ambiguous }
        let found = try locate(item, in: document)
        return Removal(before: base, after: try document.delete(found),
                       preview: preview(found), childCount: found.flattened.count - 1)
    }

    /// 편집 상자 내용을 저장 안 한 편집(`draft`)으로 둔다. 문서와 같으면 비운다.
    /// 상자가 열린 사이 로컬 파일이 바뀌면 M4 규칙대로 충돌이 된다.
    public static func setDraft(_ doc: GuideDoc, base: String, format: GuidanceDocumentFormat = .markdown,
                                item: GuidanceItem, text: String) {
        guard let content = try? replacing(base, format: format, item: item, with: text) else { return }
        let draft: String? = content == doc.content ? nil : content
        if doc.draft != draft { doc.draft = draft }
    }

    /// 항목 글을 바꿔 저장한다.
    public static func replace(_ doc: GuideDoc, base: String, format: GuidanceDocumentFormat = .markdown,
                               item: GuidanceItem, with text: String,
                               at date: Date, context: ModelContext) throws -> GuideLibrary.SaveResult {
        let content = try replacing(base, format: format, item: item, with: text)
        return try commit(doc, base: base, content: content, at: date, context: context)
    }

    /// 항목(하위 포함)을 지우고 저장한다. 저장되면 되돌리기 기록을 함께 돌려준다.
    public static func delete(_ doc: GuideDoc, base: String, format: GuidanceDocumentFormat = .markdown,
                              item: GuidanceItem,
                              at date: Date, context: ModelContext) throws -> (GuideLibrary.SaveResult, Removal) {
        let removal = try removing(base, format: format, item: item)
        let result = try commit(doc, base: base, content: removal.after, at: date, context: context)
        return (result, removal)
    }

    /// 지우기 직전 내용으로 저장한다(새 버전 app). 지운 뒤 로컬 변경이 반영됐으면 덮어쓰지 않고 충돌로 멈춘다.
    public static func undo(_ doc: GuideDoc, _ removal: Removal,
                            at date: Date, context: ModelContext) throws -> GuideLibrary.SaveResult {
        try commit(doc, base: removal.after, content: removal.before, at: date, context: context)
    }

    /// 「지움 · 앞부분」, 하위가 있으면 「지움 · 앞부분 · 하위 2개 포함」.
    public static func summary(_ removal: Removal) -> String {
        var parts = ["지움"]
        if !removal.preview.isEmpty { parts.append(removal.preview) }
        if removal.childCount > 0 { parts.append("하위 \(removal.childCount)개 포함") }
        return parts.joined(separator: " · ")
    }

    /// 알림에 보일 앞부분 글자 수
    public static let previewLength = 24

    // MARK: - 내부

    /// `base`가 앱 기록과 같을 때만 저장 경로로 넘긴다. 다르면 편집을 `draft`에 두고 충돌로.
    static func commit(_ doc: GuideDoc, base: String, content: String,
                       at date: Date, context: ModelContext) throws -> GuideLibrary.SaveResult {
        guard doc.content == base else {
            doc.draft = content
            doc.conflictContent = doc.content
            doc.isMissing = false
            try context.save()
            return .conflict
        }
        return try GuideLibrary.save(doc, content: content, at: date, context: context)
    }

    /// 다시 나눈 문서에서 같은 번호·같은 글의 항목.
    static func locate(_ item: GuidanceItem, in document: GuidanceDocument) throws -> GuidanceItem {
        guard document.isEditable else { throw Failure.notEditable }
        guard let found = document.item(id: item.id), found.kind == item.kind,
              Array(found.text.utf8) == Array(item.text.utf8)
        else { throw Failure.staleItem }
        return found
    }

    static func preview(_ item: GuidanceItem) -> String {
        let source = item.display.isEmpty ? item.text : item.display
        let line = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let plain = line.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard plain.count > previewLength else { return plain }
        return String(plain.prefix(previewLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
