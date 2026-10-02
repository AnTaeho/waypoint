import SwiftUI
import WaypointKit

/// 타일의 지금 상황 글. 길면 4줄까지 보이고 「더 보기」로 편다. 오래되면 흐리게.
struct SituationStatus: View {
    let entry: ProjectStatus.Entry
    let now: Date
    @State private var expanded = false

    var body: some View {
        let stale = entry.isStale(now: now)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(entry.text)
                .font(Theme.Situation.statusText).foregroundStyle(Theme.textSecondary)
                .lineLimit(expanded ? nil : Theme.Situation.statusLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: Theme.Spacing.s) {
                Text(meta).font(Theme.Situation.meta).foregroundStyle(Theme.textMuted)
                if stale {
                    Text("오래됨").font(Theme.captionLargeMedium).foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
                if folds {
                    Button(expanded ? "접기" : "더 보기") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .font(Theme.captionLargeMedium).foregroundStyle(Theme.liveText)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Radius.box))
        .opacity(stale ? Theme.Situation.staleOpacity : 1)
    }

    private var meta: String {
        let when = TimeFormat.relative(entry.at, now: now)
        return entry.provider.map { "\(when) · \($0.name)" } ?? when
    }

    /// 줄 수나 길이가 접힌 범위를 넘을 때만 「더 보기」를 둔다(실제 줄바꿈 수는 SwiftUI가 알려 주지 않는다).
    private var folds: Bool {
        entry.text.split(separator: "\n").count > Theme.Situation.statusLines
            || entry.text.count > Theme.Situation.statusFoldCharacters
    }
}
