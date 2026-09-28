import SwiftUI
import WaypointKit

/// 이름·카드 키 한 줄, 그 아래 개요.
struct InitFields: View {
    @Binding var form: InitForm
    let keyProblem: ProjectKey.Problem?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                labeled("이름") {
                    InitTextField(text: $form.name)
                }
                labeled("카드 키", note: keyNote) {
                    InitTextField(text: keyBinding, mono: true, invalid: keyProblem != nil)
                }
                .frame(width: Theme.Init.keyWidth)
            }
            labeled("개요") {
                InitTextField(text: $form.summary, lines: 2...4)
            }
        }
    }

    /// 입력하는 대로 대문자로 바꾼다.
    private var keyBinding: Binding<String> {
        Binding(get: { form.key }, set: { form.key = $0.uppercased() })
    }

    private var keyNote: String? {
        switch keyProblem {
        case .format: "A–Z 2–5자"
        case .taken: "사용 중"
        case nil: nil
        }
    }

    private func labeled(_ title: String, note: String? = nil, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Init.labelGap) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title).foregroundStyle(Theme.textSecondary)
                if let note {
                    Spacer(minLength: 0)
                    Text(note).foregroundStyle(Theme.liveText).lineLimit(1)
                }
            }
            .font(Theme.Init.label)
            field()
        }
    }
}

/// 테두리 있는 입력 칸.
struct InitTextField: View {
    @Binding var text: String
    var mono = false
    var invalid = false
    var lines: ClosedRange<Int>?

    var body: some View {
        Group {
            if let lines {
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(lines)
                    .padding(.vertical, Theme.Spacing.m)
            } else {
                TextField("", text: $text)
                    .frame(height: Theme.Init.fieldHeight)
            }
        }
        .textFieldStyle(.plain)
        .font(mono ? Theme.mono : Theme.Init.field)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, Theme.Init.fieldPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.button)
                .strokeBorder(invalid ? Theme.live : Theme.border, lineWidth: invalid ? Theme.Size.liveBorder : Theme.Size.cardBorder)
        }
    }
}
