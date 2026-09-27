import SwiftUI
import WaypointKit

/// 변경된 파일: 경로(모노)와 +/− 줄 수.
struct ChangedFilesList: View {
    let files: [ChangedFile]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - 1) {
            ForEach(files, id: \.path) { file in
                HStack(spacing: Theme.Spacing.s) {
                    Text(file.path)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(file.path)
                    Spacer(minLength: 0)
                    Text(CardFormat.lineDelta(added: file.added, removed: file.removed))
                        .foregroundStyle(Theme.done)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                .font(Theme.mono)
            }
        }
    }
}

/// 연결된 카드: 카드 ID(모노), 제목, 관계. 누르면 그 카드로 간다.
struct RelatedCardsList: View {
    let items: [RelatedCard]
    let open: (Card) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - 1) {
            ForEach(items) { item in
                Button { open(item.card) } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(item.card.displayID)
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: Theme.Size.linkedCardIDWidth, alignment: .leading)
                        Text(item.card.title)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(item.relation)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.liveText)
                    }
                    .font(Theme.body)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 다음 세션을 위한 메모.
struct NextSessionNote: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s - 1) {
            Text("다음 세션을 위한 메모")
                .font(Theme.inspectorSection)
                .foregroundStyle(Theme.text)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Theme.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
        }
    }
}
