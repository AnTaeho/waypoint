import Foundation

/// 화면에 보이는 시간 문구. `now`·`Calendar`를 받아 순수 함수로 계산한다.
public enum TimeFormat {

    /// 경과 시간: 「방금」「38분」「1시간」「1시간 5분」「2일 3시간」.
    public static func elapsed(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
        }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0 ? "\(days)일" : "\(days)일 \(restHours)시간"
    }

    /// 상대 시각: 「방금」「22분 전」「3시간 전」(오늘) 「어제 23:12」「3일 전」(7일 미만) 「9월 24일」「2025년 9월 24일」.
    /// 날짜 경계는 `calendar`(시간대 포함) 기준. 미래 시각은 「방금」.
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "방금" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)분 전" }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        switch days {
        case ...0:
            return "\(minutes / 60)시간 전"
        case 1:
            return String(format: "어제 %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        case 2..<7:
            return "\(days)일 전"
        default:
            let month = parts.month ?? 0, day = parts.day ?? 0
            if calendar.component(.year, from: now) == parts.year {
                return "\(month)월 \(day)일"
            }
            return "\(parts.year ?? 0)년 \(month)월 \(day)일"
        }
    }
}
