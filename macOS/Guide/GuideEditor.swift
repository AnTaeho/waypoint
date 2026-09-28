import SwiftData
import SwiftUI
import WaypointKit

/// 편집: 원문 편집기 + 취소·저장(⌘S). 저장하지 않은 내용은 문서의 `draft`로 남아 화면을 떠나도 유지된다.
struct GuideEditor: View {
    let doc: GuideDoc
    /// 저장·취소 뒤 읽기로 돌아간다.
    let done: () -> Void

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(Theme.Guide.source)
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.m)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
                }
                .padding(.horizontal, Theme.Spacing.pageH)
                .padding(.top, Theme.Spacing.l)
            HStack(spacing: Theme.Spacing.m) {
                if let error {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.liveText)
                        .lineLimit(2)
                }
                Spacer()
                Button("취소", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .font(Theme.body)
            .padding(.horizontal, Theme.Spacing.pageH)
            .padding(.vertical, Theme.Spacing.m + 2)
        }
        .onAppear(perform: load)
        .onChange(of: doc.persistentModelID) { loaded = false; load() }
        .onChange(of: text) {
            guard loaded else { return }
            let draft: String? = text == doc.content ? nil : text
            if doc.draft != draft { doc.draft = draft }
        }
        // 편집하지 않은 채 로컬 변경이 반영되면 편집기도 새 내용으로
        .onChange(of: doc.content) {
            if doc.draft == nil, text != doc.content { text = doc.content }
        }
    }

    private func load() {
        text = doc.draft ?? doc.content
        error = nil
        loaded = true
    }

    private func cancel() {
        doc.draft = nil
        try? context.save()
        loaded = false
        done()
    }

    private func save() {
        do {
            switch try GuideLibrary.save(doc, content: text, at: Date(), context: context) {
            case .saved: done()
            case .conflict: break  // 충돌이면 화면이 비교로 바뀐다
            }
        } catch {
            self.error = "저장 못 함 · \(error.localizedDescription)"
        }
    }
}
