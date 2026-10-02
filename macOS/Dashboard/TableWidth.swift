import SwiftUI

/// 작업중 표의 열 폭. nil인 열은 숨긴다.
struct ActiveColumns: Equatable {
    var file: CGFloat?
    var session: CGFloat?
}

/// 표 폭에 맞춰 열을 고른다. 제목 열에 최소 폭을 먼저 남기고, 모자라면 덜 중요한 열부터 숨긴다(최근 파일 → 세션).
enum TableWidth {
    private static let gap = Theme.Spacing.l
    private static let padding = Theme.Spacing.rowH * 2

    static func active(tableWidth: CGFloat) -> ActiveColumns {
        let c = Theme.Columns.self
        guard tableWidth > 0 else { return ActiveColumns(file: c.activeFile.lowerBound, session: c.activeSession) }
        // 카드·제목·경과 세 열
        var left = tableWidth - padding - c.activeCard - c.activeElapsed - gap * 2 - c.activeTitleMin
        var columns = ActiveColumns(file: nil, session: nil)
        guard left >= c.activeSession + gap else { return columns }
        left -= c.activeSession + gap
        columns.session = c.activeSession
        guard left >= c.activeFile.lowerBound + gap else { return columns }
        columns.file = min(left - gap, c.activeFile.upperBound)
        return columns
    }
}

extension View {
    /// 이 뷰의 폭을 `width`에 적는다.
    func readWidth(into width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width.wrappedValue = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in width.wrappedValue = new }
            }
        }
    }
}
