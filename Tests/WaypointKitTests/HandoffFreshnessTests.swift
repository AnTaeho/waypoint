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

    // 메모와 같은 시각의 파일 변경은 「이후」로 세지 않고, 0개면 변경 없음으로 적는다.
    @Test func changeAtNoteTimeIsNotCountedAndLabelSaysNoChange() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        card.nextSessionNote = "continue"
        Event.record(.note, in: h.context, card: card, at: t0 + 10, payload: ["kind": "handoff", "text": "continue"])
        Event.record(.fileChanged, in: h.context, card: card, at: t0 + 10, payload: ["path": "a.swift"])
        let same = try #require(HandoffFreshness.evaluate(card))
        #expect(same.changedFileCount == 0)
        #expect(same.label.hasSuffix("이후 기록된 파일 변경 없음"))
        Event.record(.fileChanged, in: h.context, card: card, at: t0 + 11, payload: ["path": "b.swift"])
        #expect(HandoffFreshness.evaluate(card)?.label.hasSuffix("이후 파일 1개 변경") == true)
    }

    // 인수인계가 아닌 메모와 다른 프로젝트 이름으로 남은 기록은 메모 시각을 정하지 않는다.
    @Test func onlyHandoffNotesOfThisProjectDecideWrittenAt() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
        card.nextSessionNote = "continue"
        Event.record(.note, in: h.context, card: card, at: t0 + 10, payload: ["kind": "handoff", "text": "continue"])
        Event.record(.note, in: h.context, card: card, at: t0 + 20, payload: ["kind": "criterion", "text": "조건", "isDone": true])
        #expect(HandoffFreshness.evaluate(card)?.writtenAt == t0 + 10)
        let other = makeProject(h.context, key: "OTH")
        Event.record(.note, in: h.context, project: other, card: card, at: t0 + 30, payload: ["kind": "handoff", "text": "elsewhere"])
        Event.record(.fileChanged, in: h.context, project: other, card: card, at: t0 + 40, payload: ["path": "elsewhere.swift"])
        let result = try #require(HandoffFreshness.evaluate(card))
        #expect(result.writtenAt == t0 + 10 && result.changedFileCount == 0)
    }
}
