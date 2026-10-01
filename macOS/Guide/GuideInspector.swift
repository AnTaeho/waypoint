import SwiftData
import SwiftUI
import WaypointKit

/// 지침 문서의 인스펙터: 문서 정보(로컬 경로·동기화·분량)와 버전 기록.
struct GuideInspector: View {
    let doc: GuideDoc
    @State private var shown: GuideVersion?

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                content(now: timeline.date)
            }
        }
        .background(Theme.bgPanel)
        .sheet(item: $shown) { version in
            GuideVersionSheet(doc: doc, version: version)
        }
    }

    private func content(now: Date) -> some View {
        let versions = GuideLibrary.versions(of: doc)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl + 4) {
            InspectorSection("문서 정보") {
                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.l) {
                    GridRow(alignment: .firstTextBaseline) {
                        label("로컬 경로")
                        Text(path)
                            .font(Theme.monoCaption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GridRow {
                        label("동기화")
                        Text(status(now: now))
                            .foregroundStyle(GuideFormat.state(of: doc) == .synced ? Theme.text : Theme.liveText)
                    }
                    GridRow {
                        label("분량")
                        Text(GuideFormat.size(of: doc.draft ?? doc.content))
                    }
                }
                .font(Theme.body)
                .foregroundStyle(Theme.text)
            }
            if let project = doc.project {
                InspectorSection("이 프로젝트에 걸린 지침") {
                    GuidanceAppliedList(project: project)
                }
            }
            InspectorSection("버전 기록") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(versions, id: \.persistentModelID) { version in
                        Button { shown = version } label: {
                            HStack {
                                Text(TimeFormat.timestamp(version.at, now: now, seconds: true))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(GuideFormat.sourceName(version.source))
                                    .foregroundStyle(version.source == .app ? Theme.liveText : Theme.textMuted)
                            }
                            .font(Theme.body)
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.divider)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var path: String {
        GuideLibrary.fileURL(of: doc).map { GuideFormat.displayPath($0.path) } ?? doc.relPath
    }

    private func status(now: Date) -> String {
        GuideFormat.statusText(GuideFormat.state(of: doc), lastSyncedAt: doc.lastSyncedAt, now: now)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.textMuted)
            .frame(width: Theme.Guide.inspectorLabelWidth, alignment: .leading)
    }
}
