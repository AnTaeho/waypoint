import SwiftData
import SwiftUI
import WaypointKit

/// 항목 화면의 쓰기 쪽. 없으면 보기만.
struct GuidanceItemWriter {
    var target: GuideItemTarget
    /// 나누지 않은 문서를 고칠 때 여는 전체 편집. nil이면 그 자리 상자로 문서 전체를 고친다.
    var openFullEditor: (() -> Void)?
}

/// 항목 보기: 절 머리 아래 항목 한 줄씩. 올린 줄에서 고치기(그 자리 원문 상자)·지우기(바로 지우고 되돌리기 알림).
struct GuidanceItemsView: View {
    let content: String
    let format: GuidanceDocumentFormat
    let writer: GuidanceItemWriter?

    @Environment(\.modelContext) var context
    @State var editing: Editing?
    @State var error: String?
    @State var toast: Toast?

    struct Editing {
        var item: GuidanceItem
        /// 상자를 열 때의 문서
        var base: String
        var text: String
    }

    struct Toast: Identifiable {
        let id = UUID()
        var doc: GuideDoc
        var removal: GuideItemEdit.Removal
    }

    var body: some View {
        let document = GuidanceDocument.parse(content, format: format)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error, editing == nil {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.liveText)
                        .padding(.bottom, Theme.Spacing.s)
                }
                if document.items.isEmpty {
                    Text("항목 없음")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(visibleItems(document), id: \.id) { item in
                    row(item, in: document)
                        .padding(.leading, CGFloat(item.id.count - 1) * Theme.GuideItems.indent)
                        .padding(.top, item.kind == .heading && item.id != [0] ? Theme.GuideItems.headingTop : 0)
                }
            }
            .frame(maxWidth: Theme.Guide.readMaxWidth, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.pageH)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                GuidanceUndoToast(message: GuideItemEdit.summary(toast.removal)) { undo(toast) }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: toast?.id)
        .onAppear { openLaunchEditor(document) }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.GuideItems.toastSeconds))
            if !Task.isCancelled { toast = nil }
        }
    }

    @ViewBuilder private func row(_ item: GuidanceItem, in document: GuidanceDocument) -> some View {
        if let editing, editing.item.id == item.id {
            GuidanceItemEditBox(text: editText, error: error, cancel: cancel, save: save)
        } else {
            let writable = canWrite(document)
            GuidanceItemRow(
                item: item,
                edit: writable ? { startEditing(item, in: document) } : nil,
                delete: writable && GuideItemEdit.canDelete(document) ? { delete(item) } : nil
            )
        }
    }

    /// 고치는 항목의 하위 줄은 상자 안 원문에 들어 있어 따로 보이지 않는다.
    private func visibleItems(_ document: GuidanceDocument) -> [GuidanceItem] {
        guard let id = editing?.item.id else { return document.allItems }
        return document.allItems.filter { !($0.id.count > id.count && Array($0.id.prefix(id.count)) == id) }
    }

    /// 쓸 수 있는 문서이고, 다른 편집(상자·저장 안 한 전체 편집·충돌)이 없을 때.
    private func canWrite(_ document: GuidanceDocument) -> Bool {
        guard let writer, writer.target.isWritable, document.isEditable, editing == nil else { return false }
        if case .registered(let doc) = writer.target, doc.draft != nil || doc.conflictContent != nil { return false }
        return true
    }
}
