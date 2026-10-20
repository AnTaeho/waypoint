import Foundation
import Testing
@testable import WaypointKit

@Suite struct RefreshThrottleTests {

    @Test func firstNoteFiresNow() {
        var throttle = RefreshThrottle(interval: 0.5)
        #expect(throttle.note(at: t0) == .fire)
    }

    @Test func burstSchedulesOneTrailingFire() {
        var throttle = RefreshThrottle(interval: 0.5)
        #expect(throttle.note(at: t0) == .fire)
        #expect(throttle.note(at: t0.addingTimeInterval(0.1)) == .schedule(t0.addingTimeInterval(0.5)))
        #expect(throttle.note(at: t0.addingTimeInterval(0.2)) == .ignore)
        #expect(throttle.note(at: t0.addingTimeInterval(0.6)) == .ignore)
    }

    @Test func afterTrailingFireNextNoteWaitsAgain() {
        var throttle = RefreshThrottle(interval: 0.5)
        _ = throttle.note(at: t0)
        _ = throttle.note(at: t0.addingTimeInterval(0.1))
        throttle.fireScheduled(at: t0.addingTimeInterval(0.5))
        #expect(throttle.note(at: t0.addingTimeInterval(0.7)) == .schedule(t0.addingTimeInterval(1.0)))
    }

    @Test func noteAfterQuietIntervalFiresNow() {
        var throttle = RefreshThrottle(interval: 0.5)
        _ = throttle.note(at: t0)
        #expect(throttle.note(at: t0.addingTimeInterval(0.5)) == .fire)
        #expect(throttle.note(at: t0.addingTimeInterval(3)) == .fire)
    }

    /// 0.1초마다 저장해도(원격 replay) 반영은 간격마다 한 번이고, 마지막 저장도 간격 안에 반영된다.
    @Test func steadySavesFireOncePerInterval() throws {
        var throttle = RefreshThrottle(interval: 0.5)
        var fired: [Date] = []
        var scheduled: Date?
        for step in 0..<20 {
            let now = t0.addingTimeInterval(Double(step) * 0.1)
            if let due = scheduled, due <= now {
                throttle.fireScheduled(at: due)
                fired.append(due)
                scheduled = nil
            }
            switch throttle.note(at: now) {
            case .fire: fired.append(now)
            case .schedule(let at): scheduled = at
            case .ignore: break
            }
        }
        #expect(fired.count == 4)
        let lastSave = t0.addingTimeInterval(1.9)
        #expect(try #require(scheduled).timeIntervalSince(lastSave) <= 0.5)
    }
}
