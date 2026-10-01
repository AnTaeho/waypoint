import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// MCP `card_evidence`(SPEC 7장).
@Suite struct CardEvidenceToolTests {
    func harness() throws -> (MCPHarness, Card) {
        let h = try MCPHarness()
        let card = h.project.makeCard(in: h.context, title: "a", status: .next,
                                      criteria: [Criterion("테스트 통과"), Criterion("문서")], at: t0)
        return (h, card)
    }

    @Test func recordsReportAndConfirmsWithHook() throws {
        let (h, card) = try harness()
        let r1 = try h.ok("card_evidence", ["id": "PRB-1", "criterion": 1, "command": "swift test", "outcome": "pass",
                                             "detail": "42개 통과", "sessionId": .string(MCPHarness.sessionID)])
        #expect(r1["state"] == "passed" && r1["confirmed"] == false && r1["criterion"] == 1)
        let report = try #require(CardEvidence.records(for: card).first)
        #expect(report.source == .agent && report.criterion == 0 && report.criterionText == "테스트 통과")
        #expect(report.detail == "42개 통과" && report.provider == .claude)

        CardEvidence.record(CheckRecord(at: t0 + 30, command: "swift test 2>&1", outcome: .pass, source: .hook),
                            card: card, session: h.session, in: h.context)
        let r2 = try h.ok("card_evidence", ["id": "PRB-1", "criterion": 1, "command": "swift test", "outcome": "pass"])
        #expect(r2["confirmed"] == true)
        // card_get 최근 기록에 실린다
        let got = try h.ok("card_get", ["id": "PRB-1"])
        #expect(got["recentEvents"]?.arrayValue?.contains { $0["type"] == "check" } == true)
    }

    @Test func cardLevelReportAndSkipped() throws {
        let (h, card) = try harness()
        _ = try h.ok("card_evidence", ["id": "PRB-1", "command": "swift build", "outcome": "fail"])
        _ = try h.ok("card_evidence", ["id": "PRB-1", "criterion": 2, "command": "문서 검토", "outcome": "skipped"])
        let states = CardEvidence.criteria(for: card).map(\.state)
        #expect(states == [.unverified, .skipped])
    }

    @Test func rejectsBadInput() throws {
        let (h, _) = try harness()
        #expect(try h.fails("card_evidence", ["id": "PRB-1", "criterion": 0, "command": "x", "outcome": "pass"]).contains("1–2"))
        #expect(try h.fails("card_evidence", ["id": "PRB-1", "criterion": 3, "command": "x", "outcome": "pass"]).contains("1–2"))
        #expect(try h.fails("card_evidence", ["id": "PRB-1", "criterion": .number(1.5), "command": "x", "outcome": "pass"]).contains("정수"))
        #expect(try h.fails("card_evidence", ["id": "PRB-1", "command": "x", "outcome": "unknown"]).contains("outcome"))
        #expect(try h.fails("card_evidence", ["id": "PRB-1", "command": "  ", "outcome": "pass"]).contains("command"))
        #expect(try h.fails("card_evidence", ["id": "PRB-9", "command": "x", "outcome": "pass"]).contains("카드 없음"))
        let plain = h.project.makeCard(in: h.context, title: "조건 없음", status: .next, at: t0)
        _ = plain
        #expect(try h.fails("card_evidence", ["id": "PRB-2", "criterion": 1, "command": "x", "outcome": "pass"]).contains("완료 조건이 없는"))
        #expect(try h.context.fetchCount(FetchDescriptor<Event>(predicate: #Predicate { $0.typeRaw == "check" })) == 0)
    }
}
