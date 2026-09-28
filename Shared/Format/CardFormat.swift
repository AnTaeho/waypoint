import Foundation

/// 보드 카드·카드 상세에 보이는 짧은 문구.
public enum CardFormat {

    /// 만든 곳: 「Claude」「직접 작성」.
    public static func originName(_ origin: CardOrigin) -> String {
        switch origin {
        case .claude: "Claude"
        case .manual: "직접 작성"
        }
    }

    /// 아이디어·다음 카드 아래 줄: 「Claude · 어제」「직접 작성 · 9월 24일」.
    public static func originLine(_ card: Card, now: Date, calendar: Calendar = .current) -> String {
        "\(originName(card.origin)) · \(TimeFormat.day(card.createdAt, now: now, calendar: calendar))"
    }

    public static func kindName(_ kind: CardKind) -> String {
        switch kind {
        case .task: "작업"
        case .idea: "아이디어"
        case .bug: "버그"
        }
    }

    /// 보드 칸·상태 배지 이름.
    public static func statusName(_ status: CardStatus) -> String {
        switch status {
        case .idea: "아이디어"
        case .next: "다음 할 일"
        case .active: "작업중"
        case .done: "완료"
        case .archived: "보관"
        }
    }

    /// 작업중 카드 오른쪽 위: live면 「38분째」(1분 미만 「방금」), stalled면 「멈춤 22분」.
    public static func workTime(state: CardWorkState, attachedAt: Date, lastSeenAt: Date, now: Date) -> String? {
        switch state {
        case .live:
            let elapsed = TimeFormat.elapsed(from: attachedAt, to: now)
            return elapsed == "방금" ? elapsed : "\(elapsed)째"
        case .stalled:
            return "멈춤 \(TimeFormat.elapsed(from: lastSeenAt, to: now))"
        case .none:
            return nil
        }
    }

    /// 완료 카드 아래 줄: 「어제 · 세션 2회 · 커밋 3」. 세션·커밋이 0이면 그 부분을 뺀다.
    public static func doneLine(doneAt: Date?, stats: CardWorkStats, now: Date, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let doneAt { parts.append(TimeFormat.day(doneAt, now: now, calendar: calendar)) }
        if stats.sessionCount > 0 { parts.append("세션 \(stats.sessionCount)회") }
        if stats.commitCount > 0 { parts.append("커밋 \(stats.commitCount)") }
        return parts.joined(separator: " · ")
    }

    /// 누적 작업: 「세션 1회 · 서브에이전트 1」. 둘 다 0이면 「없음」.
    public static func workTotal(_ stats: CardWorkStats) -> String {
        var parts: [String] = []
        if stats.sessionCount > 0 { parts.append("세션 \(stats.sessionCount)회") }
        if stats.subagentCount > 0 { parts.append("서브에이전트 \(stats.subagentCount)") }
        return parts.isEmpty ? "없음" : parts.joined(separator: " · ")
    }

    /// 변경 줄 수: 「+84 −12」.
    public static func lineDelta(added: Int, removed: Int) -> String {
        "+\(added) −\(removed)"
    }
}
