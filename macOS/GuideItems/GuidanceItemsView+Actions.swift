import SwiftData
import SwiftUI
import WaypointKit

/// 항목 화면 동작. 지침 문서는 상자 글을 draft로, 저장·지우기·되돌리기는 `GuideItemEdit`(저장 경로는 M4 그대로).
/// 프로젝트 밖 파일(`.file`)은 `GuidanceFileEdit`로 바뀜을 만들어 `GuidanceFileWrite`(확인·검사·백업·원자적 쓰기)로.
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
        changedOnDisk = false
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
        changedOnDisk = false
    }

    func save() {
        guard let editing, let writer else { return }
        if case .file(let source) = writer.target {
            return writeFile(reason: .edit) {
                [try GuidanceFileEdit.replacing(path: source.path, base: editing.base, format: format,
                                                item: editing.item, with: editing.text)]
            } done: { self.editing = nil }
        }
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
        if case .file(let source) = writer.target {
            var removal: GuidanceFileWrite.ChangeSet?
            return writeFile(reason: .delete) {
                let set = try GuidanceFileEdit.removing(path: source.path, base: content, format: format, item: item)
                removal = set
                return set.changes
            } done: {
                if let removal { files.showUndo(removal) }
            }
        }
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

    /// 바뀜을 만들고 메인 스레드 밖에서 쓴다. 디스크가 바뀌었으면 「바뀜」 + 「다시 읽기」.
    func writeFile(reason: GuidanceBackupStore.Reason, changes make: () throws -> [GuidanceFileWrite.Change],
                   done: @escaping @MainActor () -> Void) {
        let changes: [GuidanceFileWrite.Change]
        do {
            changes = try make()
        } catch {
            self.error = GuidanceFileRunner.message(error)
            return
        }
        busy = true
        let files = files
        Task { @MainActor in
            defer { busy = false }
            do {
                try await GuidanceFileRunner.apply(changes, context: files, reason: reason, checkRules: true)
                error = nil
                changedOnDisk = false
                done()
                writer?.reload?()
                files.didWrite()
            } catch {
                changedOnDisk = (error as? GuidanceFileWrite.Failure) == .changed
                self.error = GuidanceFileRunner.message(error)
            }
        }
    }

    /// 편집을 버리고 파일을 다시 읽는다.
    func reload() {
        editing = nil
        error = nil
        changedOnDisk = false
        writer?.reload?()
        files.didWrite()
    }

    /// `-WaypointGuideItemsEdit N`(Debug)로 화면을 확인할 때 그 항목의 편집 상자를 연다.
    func openLaunchEditor(_ document: GuidanceDocument) {
        guard editing == nil, let index = GuideLaunch.editIndex, writer?.target.isWritable == true,
              document.allItems.indices.contains(index) else { return }
        let item = document.allItems[index]
        editing = Editing(item: item, base: content, text: item.text)
    }
}
