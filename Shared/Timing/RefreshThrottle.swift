import Foundation

/// 화면 갱신 신호 묶기. 쉬던 중 온 신호는 바로 반영하고, 간격 안에 다시 오면 간격이 끝날 때 한 번 더 반영한다.
public struct RefreshThrottle: Sendable {
    public enum Decision: Equatable, Sendable {
        /// 지금 반영한다
        case fire
        /// 이 시각에 한 번 더 반영하도록 예약한다
        case schedule(Date)
        /// 이미 예약돼 있다
        case ignore
    }

    /// 화면 반영 간격(초). 저장 뒤 화면이 늦어도 이만큼이다.
    public static let defaultInterval: TimeInterval = 0.5

    public let interval: TimeInterval
    public private(set) var lastFired: Date?
    public private(set) var pending = false

    public init(interval: TimeInterval = RefreshThrottle.defaultInterval) {
        self.interval = interval
    }

    public mutating func note(at now: Date) -> Decision {
        if pending { return .ignore }
        guard let lastFired, now.timeIntervalSince(lastFired) < interval else {
            lastFired = now
            return .fire
        }
        pending = true
        return .schedule(lastFired.addingTimeInterval(interval))
    }

    /// 예약한 반영을 했다.
    public mutating func fireScheduled(at now: Date) {
        pending = false
        lastFired = now
    }
}
