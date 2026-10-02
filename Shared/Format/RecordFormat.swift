import Foundation

/// 기록 탭(TRK-47) 문구.
public enum RecordFormat {

    /// 백업 까닭: 업데이트 전·매일·직접·복원 전·지우기 전
    public static func reason(_ reason: StoreBackup.Reason) -> String {
        switch reason {
        case .upgrade: "업데이트 전"
        case .daily: "매일"
        case .manual: "직접"
        case .beforeRestore: "복원 전"
        case .beforeDelete: "지우기 전"
        }
    }

    /// 백업 크기(파일 합). 「28.4 MB」
    public static func size(_ entry: StoreBackup.Entry) -> String {
        size(bytes: entry.info.files.values.reduce(0, +))
    }

    public static func size(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    /// 백업 한 줄: 「14:22 · 매일 · 28.4 MB」
    public static func backupLine(_ entry: StoreBackup.Entry, now: Date, calendar: Calendar = .current) -> String {
        [TimeFormat.timestamp(entry.info.createdAt, now: now, calendar: calendar), reason(entry.info.reason), size(entry)]
            .joined(separator: " · ")
    }

    /// 지우기 두 번째 확인: 「프로젝트 4개 · 카드 110개」
    public static func wipeSummary(_ counts: RecordWipe.Counts) -> String {
        "프로젝트 \(counts.projects)개 · 카드 \(counts.cards)개"
    }
}
