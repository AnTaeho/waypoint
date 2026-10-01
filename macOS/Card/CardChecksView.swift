import SwiftUI
import WaypointKit

/// 카드 수준 검증 기록: 최근 것부터 결과·명령(모노)·출처·시각. 기록이 없으면 그리지 않는다.
struct CardChecksView: View {
    let records: [CheckRecord]
    /// 이 카드의 파일 변경 시각(근거 뒤 변경 표시용)
    let changes: [Date]
    let now: Date
    @State private var showsAll = false

    var body: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("검증 기록")
                    .font(Theme.sectionLarge)
                    .foregroundStyle(Theme.text)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(shown) { record in
                        CheckRow(record: record, isStale: CardEvidence.isStale(record, changes: changes), now: now)
                    }
                }
                if records.count > Theme.Evidence.listLimit {
                    Button(showsAll ? "접기" : "\(records.count - Theme.Evidence.listLimit)개 더") { showsAll.toggle() }
                        .buttonStyle(.link)
                        .font(Theme.captionLarge)
                }
            }
            .frame(maxWidth: Theme.Size.detailBodyMaxWidth, alignment: .leading)
        }
    }

    private var shown: [CheckRecord] {
        showsAll ? records : Array(records.prefix(Theme.Evidence.listLimit))
    }
}

private struct CheckRow: View {
    let record: CheckRecord
    let isStale: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Text(EvidenceFormat.outcomeName(record.outcome))
                .font(Theme.captionLargeMedium)
                .foregroundStyle(color)
                .frame(width: Theme.Evidence.outcomeWidth, alignment: .leading)
            Text(record.command)
                .font(Theme.mono)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(record.command)
            Spacer(minLength: Theme.Spacing.s)
            Text(caption)
                .font(Theme.captionLarge)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1)
                .fixedSize()
                .help(record.detail ?? "")
        }
    }

    /// 「조건 1 · 확인됨 · 이후 변경 · 14:02」
    private var caption: String {
        var parts: [String] = []
        if let criterion = record.criterion { parts.append("조건 \(criterion + 1)") }
        parts.append(EvidenceFormat.sourceName(record.source))
        if isStale { parts.append("이후 변경") }
        parts.append(TimeFormat.timestamp(record.at, now: now))
        return parts.joined(separator: " · ")
    }

    private var color: Color {
        switch record.outcome {
        case .pass: Theme.Evidence.pass
        case .fail: Theme.Evidence.fail
        case .skipped, .unknown: Theme.Evidence.muted
        }
    }
}
