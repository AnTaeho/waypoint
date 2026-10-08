import SwiftUI
import WaypointKit

extension Theme {
    /// 이슈·PR 줄과 열기 시트(TRK-68).
    enum GitHub {
        static let issueIcon = "smallcircle.filled.circle"
        static let prIcon = "arrow.triangle.pull"
        /// 종류 그림 칸(그림마다 폭이 달라 번호가 어긋나지 않게)
        static let iconWidth: CGFloat = 14
        static let number = Theme.monoCaption
        static let pill = Theme.captionLargeMedium
        static let popoverWidth: CGFloat = 380
        static let popoverMaxHeight: CGFloat = 420
        static let sheetWidth: CGFloat = 560
        static let bodyHeight: CGFloat = 220
        static let labelWidth: CGFloat = 64

        static func icon(_ kind: GitHubKind) -> String { kind == .issue ? issueIcon : prIcon }

        static func pillText(_ state: GitHubState) -> Color {
            switch state {
            case .open: Theme.done
            case .merged: Theme.next
            case .closed, .draft: Theme.textMuted
            }
        }

        static func pillFill(_ state: GitHubState) -> Color {
            switch state {
            case .open: Theme.doneBg
            case .merged, .closed: Theme.bgSunken
            case .draft: .clear
            }
        }
    }
}
