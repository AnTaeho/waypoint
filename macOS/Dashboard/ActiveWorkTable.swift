import SwiftUI
import WaypointKit

/// 작업중 표: 열 머리 + 프로젝트별 묶음. 줄을 누르면 카드 상세로 간다.
struct ActiveWorkTable: View {
    let sections: [ActiveWorkSection]
    let now: Date
    @State private var width: CGFloat = 0

    var body: some View {
        let columns = TableWidth.active(tableWidth: width)
        VStack(alignment: .leading, spacing: 0) {
            TableHeader {
                Text("카드").frame(width: Theme.Columns.activeCard, alignment: .leading)
                Text("제목").frame(maxWidth: .infinity, alignment: .leading)
                if let file = columns.file {
                    Text("최근 파일").frame(width: file, alignment: .leading)
                }
                if let session = columns.session {
                    Text("세션").frame(width: session, alignment: .leading)
                }
                Text("경과").frame(width: Theme.Columns.activeElapsed, alignment: .trailing)
            }
            ForEach(sections) { section in
                TableGroupHeader(title: section.project.name)
                ForEach(section.rows) { row in
                    NavigationLink(value: row.card) {
                        ActiveWorkRowView(row: row, now: now, columns: columns)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .readWidth(into: $width)
    }
}
