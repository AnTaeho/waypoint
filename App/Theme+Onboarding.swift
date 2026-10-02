import SwiftUI

extension Theme {
    /// 온보딩(연결 설정) 시트
    enum Onboarding {
        static let width: CGFloat = 640
        static let height: CGFloat = 560
        static let padding: CGFloat = 30
        static let gap: CGFloat = 20
        /// 도구·결과 상자 안쪽 여백
        static let boxPadding: CGFloat = 14
        static let boxRadius: CGFloat = Radius.panel
        /// 단계 표시 점
        static let stepDot: CGFloat = 7
        /// 수신 대기 화면이 연결 상태를 다시 읽는 주기(초)
        static let refreshSeconds: Double = 2
        /// 「복사됨」을 보이는 시간(초)
        static let copiedSeconds: Double = 1.5
        static let ok = Theme.done
        static let problem = Theme.liveText
        static let muted = Theme.textMuted
    }
}
