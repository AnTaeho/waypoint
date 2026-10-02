import SwiftUI
import WaypointKit

/// 항목 한 줄 자리에 여는 원문 편집 상자. ⌘↩ 저장, Esc 취소.
struct GuidanceItemEditBox: View {
    @Binding var text: String
    let error: String?
    /// 쓰는 중이면 저장을 막는다
    var busy = false
    /// 디스크가 바뀌어 저장하지 않았을 때 「다시 읽기」
    var reload: (() -> Void)?
    let cancel: () -> Void
    let save: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            TextEditor(text: $text)
                .font(Theme.Guide.source)
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: Theme.GuideItems.editMinHeight, maxHeight: Theme.GuideItems.editMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.s)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.row)
                        .strokeBorder(Theme.GuideItems.editBorder, lineWidth: Theme.Size.liveBorder)
                }
            HStack(spacing: Theme.Spacing.m) {
                if let error {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.liveText)
                        .lineLimit(2)
                }
                if let reload { Button("다시 읽기", action: reload) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("취소", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
            }
            .font(Theme.body)
        }
        .padding(.vertical, Theme.GuideItems.rowPaddingV)
        .onAppear { focused = true }
    }
}

/// 화면 아래 가운데 어두운 알림: 「지움 · 앞부분」 + 「되돌리기」(없으면 알림만).
struct GuidanceUndoToast: View {
    let message: String
    let undo: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.GuideItems.toastText)
                .lineLimit(1)
            if let undo {
                Button("되돌리기", action: undo)
                    .buttonStyle(.plain)
                    .font(Theme.bodyStrong)
                    .foregroundStyle(Theme.GuideItems.toastAction)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.GuideItems.toastBg, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        .shadow(color: Theme.GuideItems.hoverShadow, radius: Theme.Size.liveShadowRadius, y: Theme.Size.liveShadowY)
        .padding(.bottom, Theme.GuideItems.toastBottom)
    }
}
