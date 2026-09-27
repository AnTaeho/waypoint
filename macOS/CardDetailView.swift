import SwiftUI
import WaypointKit

/// 카드 상세. M1 4단계에서 채운다(완료 조건, 히스토리, 연결 세션, 변경 파일, 다음 세션 메모).
struct CardDetailView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(card.displayID)
                .font(Theme.mono)
                .foregroundStyle(Theme.textMuted)
            Text(card.title)
                .font(Theme.pageTitle)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, Theme.Spacing.pageH)
        .padding(.vertical, Theme.Spacing.pageV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .navigationTitle(card.displayID)
    }
}
