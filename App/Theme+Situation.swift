import SwiftUI

extension Theme {
    /// 대시보드 상황판(프로젝트 타일 격자, TRK-64).
    enum Situation {
        /// 타일 최소 폭. 본문 폭에 이 폭이 몇 개 들어가는지로 열 수(1~`maxColumns`)를 정한다.
        static let tileMinWidth: CGFloat = 300
        static let maxColumns = 3
        /// 지금 상황 글이 접힌 채 보이는 줄 수
        static let statusLines = 4
        /// 줄 수가 넘지 않아도 이보다 길면 접는다(한 줄에 들어가는 글자 수 어림 × 줄 수)
        static let statusFoldCharacters = 150
        /// 오래된 상황 글의 불투명도
        static let staleOpacity: Double = 0.5
        /// 타일 안 구역 사이
        static let sectionGap: CGFloat = Spacing.l
        /// 구역 안 줄 사이
        static let rowGap: CGFloat = Spacing.xs
        /// 카드 줄의 ID 열
        static let idWidth: CGFloat = 64
        static let sectionTitle = Theme.tableHeader
        static let rowTitle = Theme.body
        static let statusText = Theme.body
        static let meta = Theme.caption
        /// 나를 기다리는 세션 알약(작업중 강조색)
        static let waitingFont = Theme.captionLargeMedium
        static let waitingText = Theme.liveText
        static let waitingBackground = Theme.liveBg
    }
}
