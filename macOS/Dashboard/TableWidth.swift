import SwiftUI

/// 작업중 표의 열 폭. nil인 열은 숨긴다.
struct ActiveColumns: Equatable {
    var file: CGFloat?
    var session: CGFloat?
}

/// 프로젝트 표의 열 폭. 폴더가 nil이면 숨긴다.
struct ProjectColumns: Equatable {
    var folder: CGFloat?
    var count: CGFloat
}

/// 표 폭에 맞춰 열을 고른다. 제목·이름 열에 최소 폭을 먼저 남기고, 모자라면 덜 중요한 열부터 숨긴다
/// (작업중 표: 최근 파일 → 세션, 프로젝트 표: 폴더를 숨기고 숫자 열을 좁힌다).
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

    static func project(tableWidth: CGFloat) -> ProjectColumns {
        let c = Theme.Columns.self
        guard tableWidth > 0 else { return ProjectColumns(folder: c.projectFolder.lowerBound, count: c.projectCount) }
        // 이름·작업중·다음·아이디어·마지막 활동 다섯 열
        let left = tableWidth - padding - c.projectActivity - c.projectCount * 3 - gap * 4 - c.projectNameMin
        guard left >= c.projectFolder.lowerBound + gap else {
            return ProjectColumns(folder: nil, count: c.projectCountCompact)
        }
        return ProjectColumns(folder: min(left - gap, c.projectFolder.upperBound), count: c.projectCount)
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
