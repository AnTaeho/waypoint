import SwiftData
import SwiftUI
import WaypointKit

/// 문서 줄: 등록된 문서 이름(누르면 전환, 오른쪽 클릭으로 등록 해제), 문서 추가, 상태, 읽기/항목/편집.
struct GuideHeaderBar: View {
    let project: Project
    let docs: [GuideDoc]
    let current: GuideDoc
    @Binding var mode: GuideMode
    let select: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(docs, id: \.persistentModelID) { doc in
                        tab(doc)
                    }
                    GuideAddMenu(project: project, select: select)
                }
            }
            .scrollIndicators(.never)
            .layoutPriority(1)
            Spacer(minLength: Theme.Spacing.m)
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                statusLabel(now: timeline.date)
            }
            Picker("보기", selection: $mode) {
                Text("읽기").tag(GuideMode.read)
                Text("항목").tag(GuideMode.items)
                Text("편집").tag(GuideMode.edit)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(current.conflictContent != nil)
        }
        .padding(.horizontal, Theme.Spacing.pageH)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.bgPanel)
    }

    private func tab(_ doc: GuideDoc) -> some View {
        let selected = doc.persistentModelID == current.persistentModelID
        return Button { select(doc.persistentModelID) } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(doc.relPath)
                    .font(Theme.monoCaption)
                if GuideFormat.state(of: doc) != .synced {
                    Circle()
                        .fill(Theme.liveText)
                        .frame(width: Theme.Guide.stateDot, height: Theme.Guide.stateDot)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.textMuted)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.Guide.tabHeight)
            .background(selected ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.row)
                        .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("등록 해제") { try? GuideLibrary.unregister(doc, context: context) }
        }
    }

    private func statusLabel(now: Date) -> some View {
        let state = GuideFormat.state(of: current)
        return HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon(state))
            Text(GuideFormat.statusText(state, lastSyncedAt: current.lastSyncedAt, now: now))
        }
        .font(Theme.captionLarge)
        .foregroundStyle(state == .synced ? Theme.done : Theme.liveText)
        .lineLimit(1)
        .fixedSize()
    }

    private func icon(_ state: GuideFormat.State) -> String {
        switch state {
        case .synced: "arrow.triangle.2.circlepath"
        case .draft: "pencil"
        case .missing: "questionmark.folder"
        case .conflict: "exclamationmark.triangle"
        }
    }
}
