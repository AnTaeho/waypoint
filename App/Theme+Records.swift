import SwiftUI

extension Theme {
    /// 설정 창 「기록」 탭(TRK-47)
    enum Records {
        /// 탭 너비. 백업 줄(시각 · 까닭 · 크기 · 복원…)이 한 줄에 들어가게 사용량 탭보다 넓다.
        static let width: CGFloat = 520
        /// 탭 높이. 넘는 내용은 폼 안에서 스크롤한다.
        static let height: CGFloat = 760
        /// 「남기는 것」「어디에」 줄의 이름 열(「지침 문서」「이 Mac에만」이 한 줄에 들어가는 폭)
        static let labelWidth: CGFloat = 84
        /// 「모든 기록 지우기…」 글자. 실패·위험 표시와 같은 진한 클레이(`Evidence.fail`과 같은 값).
        static let destructive = Theme.liveText
        static let detail = Theme.textMuted
        static let detailFont = Theme.caption
    }
}
