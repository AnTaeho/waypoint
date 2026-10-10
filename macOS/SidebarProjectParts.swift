import SwiftUI
import WaypointKit

/// 사이드바 줄 앞의 키.
struct SidebarKey: View {
    let key: String
    /// 선택된 줄(파란 배경)에서는 계층 색으로
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(key)
            .font(Theme.monoSmall)
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.textMuted))
            .frame(width: Theme.Size.sidebarKeyWidth, alignment: .leading)
    }
}

/// 내 답을 기다리는 세션 수 알약.
struct SidebarWaitingPill: View {
    let count: Int
    /// 선택된 줄(파란 배경)에서는 계층 색으로
    @Environment(\.backgroundProminence) private var prominence

    private var isProminent: Bool { prominence == .increased }

    var body: some View {
        Text("\(count)")
            .font(Theme.Situation.waitingFont)
            .foregroundStyle(isProminent ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Situation.waitingText))
            .monospacedDigit().lineLimit(1).fixedSize()
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(isProminent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Theme.Situation.waitingBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            .accessibilityLabel("내 답 기다림 \(count)")
    }
}

/// 「보관됨」 구역의 줄: 키와 이름만, 흐리게.
struct SidebarArchivedRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            SidebarKey(key: project.key)
            Text(project.name)
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    /// 프로젝트 삭제 확인: 이름과 함께 지워지는 카드 수.
    func projectDeleteAlert(_ project: Binding<Project?>, delete: @escaping (Project) -> Void) -> some View {
        let title = project.wrappedValue.map { "‘\($0.name)’ 삭제" } ?? ""
        return alert(
            title,
            isPresented: Binding(get: { project.wrappedValue != nil }, set: { if !$0 { project.wrappedValue = nil } }),
            presenting: project.wrappedValue
        ) { target in
            Button("삭제", role: .destructive) { delete(target) }
            Button("취소", role: .cancel) {}
        } message: { target in
            Text(deleteMessage(cards: target.cards?.count ?? 0))
        }
    }
}

private func deleteMessage(cards: Int) -> String {
    cards == 0 ? "기록이 함께 삭제됩니다." : "카드 \(cards)개와 기록이 함께 삭제됩니다."
}
