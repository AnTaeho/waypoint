import SwiftUI

extension Theme {
    /// 지침·기억 출처 화면
    enum Guidance {
        /// 왼쪽 출처 목록 폭
        static let listWidth: CGFloat = 300
        static let listMinWidth: CGFloat = 240
        /// 목록 줄 이름(경로·파일 이름)
        static let rowTitle = Font.system(size: 12, design: .monospaced)
        /// 기억 파일 머리(name·description 등) 원문
        static let header = Font.system(size: 11.5, design: .monospaced)
        /// Codex 기억 항목 사이
        static let entrySpacing: CGFloat = 12
        /// 인스펙터 「이 프로젝트에 걸린 지침」 줄 높이
        static let appliedRowHeight: CGFloat = 26
    }
    /// 지침 문서 항목 보기(TRK-40)
    enum GuideItems {
        /// 줄 안쪽 여백
        static let rowPaddingH: CGFloat = 10
        static let rowPaddingV: CGFloat = 5
        /// 하위 항목 한 단 들여쓰기
        static let indent: CGFloat = 20
        /// 절 머리 위 여백
        static let headingTop: CGFloat = 14
        /// 절 머리 글씨(작은 굵은 회색)
        static let headingSize: CGFloat = 11.5
        /// 마우스를 올린 줄: 흰 바탕 + 옅은 그림자
        static let hoverBg = surface
        static let hoverShadow = Color(hex: 0x1F1E1D, opacity: 0.10)
        static let hoverShadowRadius: CGFloat = 3
        static let hoverShadowY: CGFloat = 1
        /// 고치기·지우기 버튼
        static let iconSize: CGFloat = 12
        static let buttonSize: CGFloat = 24
        /// 코드 블록·문서 전체 항목에 보일 원문 줄 수
        static let sourceLineLimit = 4
        /// 편집 상자
        static let editBorder = live
        static let editMinHeight: CGFloat = 56
        static let editMaxHeight: CGFloat = 320
        /// 아래 가운데 지움 알림
        static let toastBg = Color(hex: 0x141413, opacity: 0.92)
        static let toastText = Color(hex: 0xFAF9F5)
        static let toastAction = Color(hex: 0xF0B49B)
        static let toastSeconds: Double = 6
        static let toastBottom: CGFloat = 20
    }
}
