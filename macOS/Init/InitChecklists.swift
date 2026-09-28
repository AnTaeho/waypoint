import SwiftUI
import WaypointKit

/// 지침 문서 체크 목록.
struct InitGuideList: View {
    let files: [String]
    @Binding var checked: Set<String>

    var body: some View {
        InitBox(title: "지침 문서", count: files.count) {
            ForEach(files, id: \.self) { file in
                Toggle(isOn: toggle(file, in: $checked)) {
                    Text(file)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

/// 초기 카드 체크 목록. 오른쪽에 상태(다음·아이디어).
struct InitCardList: View {
    let cards: [ProjectDraft.SeedCard]
    @Binding var checked: Set<UUID>

    var body: some View {
        InitBox(title: "초기 카드", count: cards.count) {
            ForEach(cards) { card in
                Toggle(isOn: toggle(card.id, in: $checked)) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        Text(card.title)
                            .font(Theme.body)
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(card.status == .idea ? "아이디어" : "다음")
                            .font(Theme.caption)
                            .foregroundStyle(card.status == .idea ? Theme.textMuted : Theme.next)
                    }
                }
                .toggleStyle(.checkbox)
                .help(card.body)
            }
        }
    }
}

/// 테두리 상자: 제목 · 개수, 내용이 길면 스크롤.
struct InitBox<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Init.boxRowGap) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title).foregroundStyle(Theme.text)
                Text("\(count)").foregroundStyle(Theme.textMuted).monospacedDigit()
            }
            .font(Theme.section)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Init.boxRowGap) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .padding(Theme.Init.boxPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
        }
    }
}

/// 집합에 들어 있는지를 체크 상자로.
private func toggle<T: Hashable & Sendable>(_ item: T, in set: Binding<Set<T>>) -> Binding<Bool> {
    Binding(
        get: { set.wrappedValue.contains(item) },
        set: { isOn in
            if isOn { set.wrappedValue.insert(item) } else { set.wrappedValue.remove(item) }
        }
    )
}
