import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 로컬 신뢰성 지표·재개 시간·진단 내보내기(TRK-11).
@Suite struct ReliabilityMetricsTests {
    @Test func nearestRankPercentiles() throws {
        let s = try #require(ReliabilityMetrics.summary((1...100).map(Double.init).shuffled()))
        #expect(s.count == 100 && s.p50 == 50 && s.p95 == 95 && s.max == 100)
        let one = try #require(ReliabilityMetrics.summary([7]))
        #expect(one.p50 == 7 && one.p95 == 7 && one.max == 7)
        let twenty = try #require(ReliabilityMetrics.summary((1...20).map(Double.init)))
        #expect(twenty.p95 == 19)
        #expect(ReliabilityMetrics.summary([]) == nil)
    }

    @Test func receiptsKeepOnlyRecentSamplesInMilliseconds() {
        var m = ReliabilityMetrics(since: t0)
        m.recordReceipt(receivedAt: t0, savedAt: t0 + 0.004, shownAt: t0 + 0.010)
        #expect(abs(m.saveMs[0] - 4) < 0.001 && abs(m.displayMs[0] - 10) < 0.001)
        m.recordReceipt(receivedAt: t0, savedAt: t0 - 1, shownAt: t0 - 1) // 시계가 거꾸로 가도 음수 없음
        #expect(m.saveMs[1] == 0)
        for i in 0..<(ReliabilityMetrics.receiptLimit + 5) {
            m.recordReceipt(receivedAt: t0, savedAt: t0 + Double(i) / 1000, shownAt: t0 + Double(i) / 1000)
        }
        #expect(m.saveMs.count == ReliabilityMetrics.receiptLimit)
        #expect(abs((m.saveMs.last ?? 0) - Double(ReliabilityMetrics.receiptLimit + 4)) < 0.001)
        for i in 0..<(ReliabilityMetrics.resumeLimit + 3) { m.recordResume(seconds: Double(i)) }
        #expect(m.resumeSeconds.count == ReliabilityMetrics.resumeLimit)
    }

    @Test func absorbResultsAddUp() {
        var m = ReliabilityMetrics(since: t0)
        m.recordAbsorb(.init(processed: 5, skipped: 1, retryPending: true))
        m.recordAbsorb(.init(processed: 2, skipped: 0, retryPending: false))
        #expect(m.recovery.absorbed == 7 && m.recovery.quarantined == 1 && m.recovery.preserved == 1)
    }

    @Test func storedFileHoldsNumbersOnlyAndReadsOlderShape() throws {
        var m = ReliabilityMetrics(since: t0)
        m.recordReceipt(receivedAt: t0, savedAt: t0 + 0.01, shownAt: t0 + 0.02)
        m.recordResume(seconds: 45)
        m.failures.invalidInput = 2
        m.recovery.sessionsClosed = 3
        let data = try JSONEncoder().encode(m)
        #expect(try JSONDecoder().decode(ReliabilityMetrics.self, from: data) == m)
        // 문자열 값이 하나도 없다: 프로젝트·경로·세션 ID·대화를 담을 자리가 없다
        func strings(_ value: Any) -> [String] {
            switch value {
            case let s as String: [s]
            case let a as [Any]: a.flatMap(strings)
            case let d as [String: Any]: d.values.flatMap(strings)
            default: []
            }
        }
        #expect(strings(try JSONSerialization.jsonObject(with: data)).isEmpty)
        let older = try JSONDecoder().decode(ReliabilityMetrics.self, from: Data(#"{"since":1}"#.utf8))
        #expect(older.saveMs.isEmpty && older.failures == .init())
    }

    @Test func durationLabels() {
        #expect(ReliabilityMetrics.duration(0.2) == "0.20초")
        #expect(ReliabilityMetrics.duration(45) == "45초")
        #expect(ReliabilityMetrics.duration(125) == "2분 5초")
        #expect(ReliabilityMetrics.duration(180) == "3분")
    }

    // MARK: 재개 시간

    @Test func resumeTimeRunsFromFirstCopyToAttachTime() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "재개", status: .next, at: t0)
        var tracker = ResumeTracker()
        tracker.copied(CardResumeAttempt(card: card, provider: .claude, at: t0))
        // 도구를 바꿔 다시 복사해도 시작은 처음 복사
        tracker.copied(CardResumeAttempt(card: card, provider: .codex, at: t0 + 20))
        #expect(tracker.check([card], now: t0 + 30).isEmpty)
        let session = makeSession(h.context, h.project, id: "codex:new")
        session.provider = .codex
        CardLifecycle.attach(card, session, at: t0 + 45, in: h.context)
        // 10초 점검이 늦게 봐도 연결 시각으로 잰다
        #expect(tracker.check([card], now: t0 + 55) == [45])
        #expect(tracker.isEmpty)
    }

    @Test func resumeIgnoresPreviousSessionsAndDropsUnavailableOrExpired() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "재개", status: .next, at: t0)
        let old = makeSession(h.context, h.project, id: "old")
        CardLifecycle.attach(card, old, at: t0, in: h.context)
        CardLifecycle.detach(card, old, at: t0 + 1, in: h.context)
        var tracker = ResumeTracker()
        tracker.copied(CardResumeAttempt(card: card, provider: .claude, at: t0 + 2))
        CardLifecycle.attach(card, old, at: t0 + 3, in: h.context) // 예전 세션이 다시 붙은 것은 재개가 아니다
        #expect(tracker.check([card], now: t0 + 4).isEmpty && !tracker.isEmpty)
        // 카드가 사라지면 뺀다
        #expect(tracker.check([], now: t0 + 5).isEmpty && tracker.isEmpty)

        let other = h.project.makeCard(in: h.context, title: "만료", status: .next, at: t0)
        tracker.copied(CardResumeAttempt(card: other, provider: .claude, at: t0))
        #expect(tracker.check([other], now: t0 + ResumeTracker.lifetime + 1).isEmpty && tracker.isEmpty)

        let done = h.project.makeCard(in: h.context, title: "완료", status: .next, at: t0)
        tracker.copied(CardResumeAttempt(card: done, provider: .claude, at: t0))
        done.status = .done
        #expect(tracker.check([done], now: t0 + 1).isEmpty && tracker.isEmpty)
    }

    // 복사하고 딱 하루 뒤에 연결을 알아채도 재개 시간으로 센다.
    @Test func resumeStillCountsExactlyAtLifetime() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "재개", status: .next, at: t0)
        var tracker = ResumeTracker()
        tracker.copied(CardResumeAttempt(card: card, provider: .claude, at: t0))
        CardLifecycle.attach(card, makeSession(h.context, h.project, id: "new"), at: t0 + 45, in: h.context)
        #expect(tracker.check([card], now: t0 + ResumeTracker.lifetime) == [45])
    }
}
