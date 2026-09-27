import SwiftUI

/// 표 머리 행 아래 구분선. 열 배치는 호출 쪽 `content`가 정한다.
struct TableHeader<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.l) { content }
                .font(Theme.tableHeader)
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.rowH)
                .padding(.bottom, Theme.Spacing.s - 1)
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

/// 표 안의 프로젝트별 그룹 머리.
struct TableGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.tableHeader)
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.rowH)
            .padding(.top, Theme.Spacing.rowH)
            .padding(.bottom, Theme.Spacing.xs)
    }
}
