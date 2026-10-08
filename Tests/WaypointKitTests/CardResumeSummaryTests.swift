import Foundation
import Testing
@testable import WaypointKit

@Suite struct CardResumeSummaryTests {
    @Test func gathersGoalRemainingUnverifiedAndNoteTime() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "Resume target", status: .next, at: t0)
        card.body = "\n## 영수증 OCR을 **카드**에 붙인다\n자세한 설명"
        card.criteria = [Criterion("checked, no evidence", isDone: true), Criterion("passed"),
                         Criterion("failed", isDone: true), Criterion("skipped")]
        for (index, outcome) in [(1, CheckOutcome.pass), (2, .fail), (3, .skipped)] {
            CardEvidence.record(CheckRecord(at: t0, command: "swift test --filter Case\(index)", outcome: outcome,
                source: .agent, criterion: index, criterionText: card.criteria[index].text),
                card: card, session: nil, in: h.context)
        }
        card.nextSessionNote = "검증부터"
        Event.record(.note, in: h.context, card: card, at: t0 + 5, payload: ["kind": "handoff", "text": "검증부터"])

        let summary = CardResumeSummary(card: card)
        #expect(summary.title == "Resume target")
        #expect(summary.goalLine == "영수증 OCR을 **카드**에 붙인다")
        #expect(summary.remaining.map(\.number) == [2, 4])
        #expect(summary.unverified.map(\.number) == [1, 3])
        #expect(summary.unverified.map(\.evidence) == ["미검증", "실패 · 보고"])
        #expect(summary.unverified.map(\.isFailure) == [false, true])
        #expect(summary.note == "검증부터" && summary.freshness?.writtenAt == t0 + 5)

        // 근거 뒤 파일이 바뀌면 통과한 조건도 미검증 쪽으로 온다. 건너뜀은 넣지 않는다.
        Event.record(.fileChanged, in: h.context, card: card, at: t0 + 10, payload: ["path": "a.swift"])
        let changed = CardResumeSummary(card: card)
        #expect(changed.unverified.map(\.number) == [1, 2, 3])
        #expect(changed.unverified[1].evidence == "변경 후 미검증 · 보고" && !changed.unverified[2].isFailure)
        #expect(changed.freshness?.changedFileCount == 1)

        // 복사 문맥과 같은 항목을 가리킨다.
        let text = try #require(CardResumeContext.text(card: card, provider: .claude))
        for item in changed.remaining { #expect(text.contains("- \(item.text)")) }
        for item in changed.unverified {
            #expect(text.contains("조건 \(item.number) ") && text.contains("\(item.text) · \(item.evidence ?? "")"))
        }
    }

    @Test func emptyCardHasNoGoalLineOrNote() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "empty", status: .next, at: t0)
        card.body = "  \n# \n"
        let summary = CardResumeSummary(card: card)
        #expect(summary.goalLine == nil && summary.note == nil && summary.freshness == nil)
        #expect(summary.remaining.isEmpty && summary.unverified.isEmpty)
        #expect(CardResumeSummary.firstLine("- [ ] 목록 첫 줄") == "[ ] 목록 첫 줄")
        #expect(CardResumeSummary.firstLine("> 인용") == "인용")
    }

    // 남은 조건 목록은 근거가 실패여도 실패 표시를 달지 않는다(실패 표시는 미검증 목록의 몫).
    @Test func remainingItemsCarryNoFailureMark() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "failing", status: .next, at: t0)
        card.criteria = [Criterion("still open")]
        CardEvidence.record(CheckRecord(at: t0, command: "swift test", outcome: .fail, source: .agent,
                                        criterion: 0, criterionText: "still open"), card: card, session: nil, in: h.context)
        let summary = CardResumeSummary(card: card)
        #expect(summary.remaining.map(\.isFailure) == [false])
        #expect(summary.unverified.map(\.isFailure) == [true])
    }
}
