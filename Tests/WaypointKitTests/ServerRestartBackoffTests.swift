import Foundation
import Testing
@testable import WaypointKit

@Suite struct ServerRestartBackoffTests {

    @Test func delaysDoubleUpToFiveMinutes() {
        let delays = (0..<8).map { ServerRestartBackoff.delay(afterAttempts: $0) }
        #expect(delays == [10, 20, 40, 80, 160, 300, 300, 300])
        #expect(ServerRestartBackoff.delay(afterAttempts: 1000) == 300)
    }

    @Test func firstAttemptIsDueImmediately() {
        #expect(ServerRestartBackoff().isDue(now: t0))
    }

    @Test func waitsUntilNextAttempt() {
        var backoff = ServerRestartBackoff()
        backoff.recordAttempt(now: t0)
        #expect(!backoff.isDue(now: t0.addingTimeInterval(9)))
        #expect(backoff.isDue(now: t0.addingTimeInterval(10)))
        backoff.recordAttempt(now: t0.addingTimeInterval(10))
        #expect(!backoff.isDue(now: t0.addingTimeInterval(29)))
        #expect(backoff.isDue(now: t0.addingTimeInterval(30)))
    }

    /// 10초 점검마다 물어도 실제 다시 여는 것은 10·20·40초… 간격이다.
    @Test func tenSecondChecksFollowBackoff() {
        var backoff = ServerRestartBackoff()
        var attemptedAt: [TimeInterval] = []
        for tick in stride(from: 0.0, through: 300, by: 10) {
            let now = t0.addingTimeInterval(tick)
            if backoff.isDue(now: now) {
                backoff.recordAttempt(now: now)
                attemptedAt.append(tick)
            }
        }
        #expect(attemptedAt == [0, 10, 30, 70, 150])
    }

    @Test func resetStartsOver() {
        var backoff = ServerRestartBackoff()
        backoff.recordAttempt(now: t0)
        backoff.recordAttempt(now: t0.addingTimeInterval(10))
        backoff.reset()
        #expect(backoff.attempts == 0)
        #expect(backoff.isDue(now: t0.addingTimeInterval(11)))
    }
}
