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
}
