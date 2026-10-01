import Foundation
import Testing
@testable import WaypointKit

@Suite struct HandoffFreshnessTests {
    @Test func usesMatchingNoteAndDistinctFilesAfterIt() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        card.nextSessionNote = "continue"
        Event.record(.note, in: h.context, card: card, at: t0 + 10, payload: ["kind": "handoff", "text": "continue"])
        for offset in [0.0, 10, 20, 30] {
            Event.record(.fileChanged, in: h.context, card: card, at: t0 + offset, payload: ["path": "a.swift"])
        }
        let other = h.project.makeCard(in: h.context, title: "other", status: .next, at: t0)
        Event.record(.fileChanged, in: h.context, card: other, at: t0 + 40, payload: ["path": "b.swift"])
        card.updatedAt = t0 + 50
        let result = try #require(HandoffFreshness.evaluate(card))
        #expect(result.writtenAt == t0 + 10 && result.changedFileCount == 1)
        #expect(CardResumeContext.text(card: card, provider: .codex)?.contains("이후 파일 1개 변경") == true)
        Event.record(.note, in: h.context, card: card, at: t0 + 60, payload: ["kind": "handoff", "text": "continue"])
        #expect(HandoffFreshness.evaluate(card)?.changedFileCount == 0)
        #expect(HandoffFreshness.evaluate(card)?.writtenAt == t0 + 60)
    }

    @Test func missingOrMismatchedHistoryNeverUsesCardUpdatedAt() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        #expect(HandoffFreshness.evaluate(card) == nil)
        card.nextSessionNote = "current"
        #expect(HandoffFreshness.evaluate(card)?.writtenAt == nil)
        Event.record(.note, in: h.context, card: card, at: t0, payload: ["kind": "handoff", "text": "current"])
        Event.record(.note, in: h.context, card: card, at: t0 + 10, payload: ["kind": "handoff", "text": "different"])
        card.updatedAt = t0 + 20
        #expect(HandoffFreshness.evaluate(card)?.writtenAt == nil)
        #expect(HandoffFreshness.evaluate(card)?.label == "메모 작성 시각 알 수 없음")
        card.nextSessionNote = " \n "
        #expect(HandoffFreshness.evaluate(card) == nil)
    }
}
