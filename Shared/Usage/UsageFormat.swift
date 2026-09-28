import Foundation

/// 사용량 게이지·메뉴 문구. `now`·`Calendar`를 받아 순수 함수로 계산한다.
public enum UsageFormat {

    public static let fiveHourLabel = "5시간"
    public static let sevenDayLabel = "7일"

    /// 「42%」
    public static func percent(_ window: UsageSnapshot.Window, now: Date) -> String {
        "\(window.percent(at: now))%"
    }

    /// 메뉴 한 줄: 「사용량 5시간 42% · 7일 18%」. 창이 하나만 있으면 그것만.
    public static func menuLine(_ snapshot: UsageSnapshot, now: Date) -> String {
        var parts: [String] = []
        if let w = snapshot.fiveHour { parts.append("\(fiveHourLabel) \(percent(w, now: now))") }
        if let w = snapshot.sevenDay { parts.append("\(sevenDayLabel) \(percent(w, now: now))") }
        return "사용량 " + parts.joined(separator: " · ")
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

    /// 게이지 도움말: 「오후 3:20에 초기화」, 기록이 오래됐으면 「오후 3:20에 초기화 · 45분 전 기준」.
    /// 초기화 시각을 모르거나 이미 지났으면 그 부분은 뺀다. 남는 것이 없으면 nil.
    public static func help(
        _ window: UsageSnapshot.Window, capturedAt: Date, now: Date, calendar: Calendar = .current
    ) -> String? {
        var parts: [String] = []
        if let resetsAt = window.resetsAt, resetsAt > now {
            parts.append("\(resetTime(resetsAt, now: now, calendar: calendar))에 초기화")
        }
        if now.timeIntervalSince(capturedAt) > UsageSnapshot.staleAfter {
            parts.append("\(TimeFormat.relative(capturedAt, now: now, calendar: calendar)) 기준")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
