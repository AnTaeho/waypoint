import SwiftUI

extension Theme {
    /// 같은 파일 작업 중 표시(TRK-17). 붉은 계열 토큰이 따로 없어 작업중 강조색(진한 클레이)을 쓴다.
    enum Overlap {
        static let text = Theme.liveText
        static let background = Theme.liveBg
        static let font = Theme.captionLargeMedium
        static let icon = "doc.on.doc"
        static let popoverWidth: CGFloat = 320
        /// 펼친 목록에서 상대 하나마다 보이는 파일 수
        static let fileLimit = 12
    }
}
