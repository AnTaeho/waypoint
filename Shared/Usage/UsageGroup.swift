import Foundation

/// 도구 하나(Claude·Codex)의 사용량 묶음. 한도마다 기간 이름표와 창 하나.
public struct UsageGroup: Equatable, Sendable {

    public enum Tool: String, CaseIterable, Sendable {
        case claude, codex

        public var title: String {
            switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            }
        }
    }

    public struct Limit: Equatable, Sendable {
        /// 「5시간」「7일」
        public var label: String
        /// 기간(분). 정렬에 쓴다.
        public var minutes: Int
        public var window: UsageSnapshot.Window

        public init(label: String, minutes: Int, window: UsageSnapshot.Window) {
            self.label = label
            self.minutes = minutes
            self.window = window
        }

        public init(minutes: Int, window: UsageSnapshot.Window) {
            self.init(label: UsageFormat.windowLabel(minutes: minutes), minutes: minutes, window: window)
        }
    }

    public var tool: Tool
    /// 짧은 기간부터
    public var limits: [Limit]
    public var capturedAt: Date

    public init(tool: Tool, limits: [Limit], capturedAt: Date) {
        self.tool = tool
        self.limits = limits.sorted { $0.minutes < $1.minutes }
        self.capturedAt = capturedAt
    }

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) > UsageSnapshot.staleAfter
    }
}

extension UsageSnapshot {
    /// 5시간 = 300분, 7일 = 10080분
    public static let fiveHourMinutes = 5 * 60
    public static let sevenDayMinutes = 7 * 24 * 60

    /// 게이지·메뉴에 쓰는 Claude 묶음
    public var group: UsageGroup {
        var limits: [UsageGroup.Limit] = []
        if let fiveHour { limits.append(.init(minutes: Self.fiveHourMinutes, window: fiveHour)) }
        if let sevenDay { limits.append(.init(minutes: Self.sevenDayMinutes, window: sevenDay)) }
        return UsageGroup(tool: .claude, limits: limits, capturedAt: capturedAt)
    }
}
