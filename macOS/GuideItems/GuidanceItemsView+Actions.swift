import SwiftData
import SwiftUI
import WaypointKit

/// 항목 화면 동작: 상자 글을 draft로, 저장·지우기·되돌리기는 `GuideItemEdit`(저장 경로는 M4 그대로).
extension GuidanceItemsView {
    var editText: Binding<String> {
        Binding {
            editing?.text ?? ""
        } set: { text in
            editing?.text = text
            if case .registered(let doc) = writer?.target, let editing {
                GuideItemEdit.setDraft(doc, base: editing.base, format: format, item: editing.item, text: text)
            }
        }
    }

    func startEditing(_ item: GuidanceItem, in document: GuidanceDocument) {
        error = nil
        if document.isAmbiguous, let open = writer?.openFullEditor { return open() }
        editing = Editing(item: item, base: content, text: item.text)
    }

    func cancel() {
        if case .registered(let doc) = writer?.target, doc.draft != nil {
            doc.draft = nil
            try? context.save()
        }
        editing = nil
        error = nil
    }

    func save() {
        guard let editing, let writer else { return }
        perform {
            guard let doc = try writer.target.document(at: Date(), context: context) else { return }
            _ = try GuideItemEdit.replace(doc, base: editing.base, format: format, item: editing.item,
                                          with: editing.text, at: Date(), context: context)
            // 충돌이면 위 화면이 비교로 바뀐다
            self.editing = nil
        }
    }

    func delete(_ item: GuidanceItem) {
        guard let writer else { return }
        perform {
            guard let doc = try writer.target.document(at: Date(), context: context) else { return }
            let (result, removal) = try GuideItemEdit.delete(doc, base: content, format: format, item: item,
                                                             at: Date(), context: context)
            if result == .saved { toast = Toast(doc: doc, removal: removal) }
        }
    }

    func undo(_ toast: Toast) {
        self.toast = nil
        perform { _ = try GuideItemEdit.undo(toast.doc, toast.removal, at: Date(), context: context) }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch GuideItemEdit.Failure.staleItem {
            error = "항목이 바뀜"
        } catch {
            self.error = "저장 못 함 · \(error.localizedDescription)"
        }
    }

    /// `-WaypointGuideItemsEdit N`(Debug)로 화면을 확인할 때 그 항목의 편집 상자를 연다.
    func openLaunchEditor(_ document: GuidanceDocument) {
        guard editing == nil, let index = GuideLaunch.editIndex, writer?.target.isWritable == true,
              document.allItems.indices.contains(index) else { return }
        let item = document.allItems[index]
        editing = Editing(item: item, base: content, text: item.text)
    }
}
