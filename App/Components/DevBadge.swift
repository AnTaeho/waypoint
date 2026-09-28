import SwiftUI
import WaypointKit

/// 개발용(Waypoint Dev)에서만 사이드바 머리에 뜨는 작은 「Dev」 표시. 평소용과 함께 떠 있을 때 창을 가려 보게 한다.
struct DevBadge: View {
    var body: some View {
        if AppInstance.current.isDev {
            HStack {
                Text("Dev")
                    .font(Theme.Dev.badgeFont)
                    .foregroundStyle(Theme.Dev.badgeText)
                    .padding(.horizontal, Theme.Dev.badgePaddingH)
                    .padding(.vertical, Theme.Dev.badgePaddingV)
                    .background(Theme.Dev.badgeBg, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }
}
