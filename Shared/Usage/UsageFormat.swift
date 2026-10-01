import Foundation

/// 사용량 게이지·메뉴 문구. `now`·`Calendar`를 받아 순수 함수로 계산한다.
public enum UsageFormat {

    public static let fiveHourLabel = windowLabel(minutes: UsageSnapshot.fiveHourMinutes)
    public static let sevenDayLabel = windowLabel(minutes: UsageSnapshot.sevenDayMinutes)

    /// 한도 기간 이름표: 300 → 「5시간」, 10080 → 「7일」, 43200 → 「30일」, 90 → 「90분」.
    public static func windowLabel(minutes: Int) -> String {
        if minutes > 0, minutes % 1440 == 0 { return "\(minutes / 1440)일" }
        if minutes > 0, minutes % 60 == 0 { return "\(minutes / 60)시간" }
        return "\(minutes)분"
    }

    /// 「42%」
    public static func percent(_ window: UsageSnapshot.Window, now: Date) -> String {
        "\(window.percent(at: now))%"
    }

    /// 묶음 하나: 「Claude 5시간 42% · 7일 18%」
    public static func groupLine(_ group: UsageGroup, now: Date) -> String {
        let limits = group.limits.map { "\($0.label) \(percent($0.window, now: now))" }
        return group.tool.title + " " + limits.joined(separator: " · ")
    }

    /// 메뉴 줄: 「사용량 Claude 5시간 42% · 7일 18% / Codex 7일 12%」. 이 길이를 넘으면 도구마다 한 줄씩.
    public static let menuLineMaxLength = 44

    public static func menuLines(_ groups: [UsageGroup], now: Date) -> [String] {
        let parts = groups.filter { !$0.limits.isEmpty }.map { groupLine($0, now: now) }
        guard !parts.isEmpty else { return [] }
        let single = "사용량 " + parts.joined(separator: " / ")
        if parts.count == 1 || single.count <= menuLineMaxLength { return [single] }
        return ["사용량 " + parts[0]] + parts.dropFirst()
    }

    /// 초기화 시각: 오늘이면 「오후 3:20」, 내일이면 「내일 오전 9:00」, 그 뒤면 「10월 2일 오후 3:20」.
    public static func resetTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let clock = String(format: "%@ %d:%02d", hour < 12 ? "오전" : "오후", hour % 12 == 0 ? 12 : hour % 12, parts.minute ?? 0)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case ...0: return clock
        case 1: return "내일 \(clock)"
        default: return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(clock)"
        }
    }

    /// 늘 보이는 짧은 초기화 시각: 오늘 「오후 3:20」, 내일 「내일 오전 9:00」, 그 뒤 「10월 7일」.
    /// 초기화 시각을 모르거나 이미 지났으면 nil.
    public static func resetShort(_ window: UsageSnapshot.Window, now: Date, calendar: Calendar = .current) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: resetsAt)
        ).day ?? 0
        guard days >= 2 else { return resetTime(resetsAt, now: now, calendar: calendar) }
        let parts = calendar.dateComponents([.month, .day], from: resetsAt)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
    }

    /// 묶음 도움말: 「방금 기준」「45분 전 기준」
    public static func basis(capturedAt: Date, now: Date, calendar: Calendar = .current) -> String {
        "\(TimeFormat.relative(capturedAt, now: now, calendar: calendar)) 기준"
    }
}
