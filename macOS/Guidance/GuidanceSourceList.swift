import SwiftUI
import WaypointKit

/// 출처 목록. 기억 폴더는 접혀 있다.
struct GuidanceSourceList: View {
    let snapshot: GuidanceSnapshot
    let projects: [Project]
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(GuidanceSections.build(snapshot, projects: projects)) { section in
                Section {
                    ForEach(section.files) { source in
                        GuidanceSourceRow(source: source, base: section.base).tag(source.path)
                    }
                    ForEach(section.memory) { group in
                        DisclosureGroup {
                            ForEach(group.sources) { source in
                                GuidanceSourceRow(source: source, base: nil).tag(source.path)
                            }
                        } label: {
                            Text(group.title)
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(group.title)
                        }
                    }
                } header: {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(section.title).font(Theme.tableHeader)
                        if let subtitle = section.subtitle {
                            Text(subtitle).font(Theme.monoSmall).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.bgPanel)
    }
}

/// 줄: 이름(경로·파일 이름) + 아래 짧은 사실(도구·항목 수).
struct GuidanceSourceRow: View {
    let source: GuidanceSource
    let base: String?
    /// 선택된 줄(파란 배경)에서는 고정 색 대신 계층 색을 써서 글자가 묻히지 않게 한다.
    @Environment(\.backgroundProminence) private var prominence

    private var isProminent: Bool { prominence == .increased }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(GuidanceFormat.title(source, base: base))
                .font(Theme.Guidance.rowTitle)
                .foregroundStyle(isProminent ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.text))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(caption)
                .font(Theme.caption)
                .foregroundStyle(isProminent ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.textMuted))
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .help(GuideFormat.displayPath(source.path))
    }

    private var caption: String {
        source.isMemory
            ? GuidanceFormat.count(source)
            : "\(GuidanceFormat.toolName(source.tool)) · \(GuidanceFormat.count(source))"
    }
}
