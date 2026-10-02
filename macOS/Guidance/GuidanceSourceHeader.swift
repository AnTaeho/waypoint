import SwiftUI
import WaypointKit

/// 출처 내용 위 한 줄: 경로(선택 가능) · 짧은 사실(열린 세션 등) · 「Claude · 항목 3 · 1.2KB · 2분 전」 · 「백업 N」 · 읽기/항목.
struct GuidanceSourceHeader: View {
    let source: GuidanceSource
    @Binding var showsItems: Bool
    /// 사실 앞에 붙는 짧은 사실(`liveText`)
    let notes: [String]
    let backupCount: Int
    let openBackups: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: Theme.Spacing.m) {
                Text(GuideFormat.displayPath(source.path))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.Spacing.m)
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.liveText)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(facts(now: timeline.date))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .fixedSize()
                if backupCount > 0 {
                    Button("백업 \(backupCount)", action: openBackups)
                        .buttonStyle(.link)
                        .font(Theme.caption)
                        .fixedSize()
                }
                if GuidanceDocumentFormat(kind: source.kind) != nil {
                    Picker("보기", selection: $showsItems) {
                        Text("읽기").tag(false)
                        Text("항목").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Spacing.pageH)
            .frame(height: Theme.Size.rowHeight)
            .background(Theme.bgPanel)
        }
    }

    private func facts(now: Date) -> String {
        let base = GuidanceFormat.facts(source)
        guard let modified = source.modifiedAt else { return base }
        return "\(base) · \(TimeFormat.relative(modified, now: now))"
    }
}
