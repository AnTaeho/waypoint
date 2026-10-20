import Foundation

/// 열지 못한 로컬 서버를 다시 여는 간격. 10초에서 시작해 두 배씩 늘리고 5분에서 멈춘다. 열리면 처음부터.
public struct ServerRestartBackoff: Sendable {
    public static let initial: TimeInterval = 10
    public static let maximum: TimeInterval = 5 * 60

    public private(set) var attempts = 0
    public private(set) var nextAttemptAt: Date?

    public init() {}

    /// 다시 연 횟수에 따른 다음 간격
    public static func delay(afterAttempts attempts: Int) -> TimeInterval {
        min(initial * pow(2, Double(min(attempts, 16))), maximum)
    }

    /// 실패를 처음 본 때는 바로, 그 뒤에는 정한 시각이 지나야 다시 연다.
    public func isDue(now: Date) -> Bool {
        guard let nextAttemptAt else { return true }
        return now >= nextAttemptAt
    }

    public mutating func recordAttempt(now: Date) {
        nextAttemptAt = now.addingTimeInterval(Self.delay(afterAttempts: attempts))
        attempts += 1
    }

    public mutating func reset() {
        attempts = 0
        nextAttemptAt = nil
    }
}
