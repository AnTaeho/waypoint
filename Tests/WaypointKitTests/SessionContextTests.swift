import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct SessionContextTests {
    @Test func listsNextOthersAndNotes() throws {
        let h = try HookHarness()
        let p = h.project
        for i in 1...6 { p.makeCard(in: h.context, title: "다음 \(i)", status: .next, at: t0) }
        let busy = p.makeCard(in: h.context, title: "다른 작업", status: .next, at: t0)
        busy.nextSessionNote = "승인금액 케이스 남음"
        let other = makeSession(h.context, p, id: "0ther-session", startedAt: t0, lastSeenAt: t0)
        CardLifecycle.attach(busy, other, at: t0, in: h.context)

        let text = try #require(try h.send("doc-SessionStart", at: t0 + 60))
        let lines = text.components(separatedBy: "\n")
        #expect(lines == [
            "Waypoint: LDG (가계부 앱)",
            "sessionId: \(HookHarness.sessionID)",
            "다음 할 일:",
            "- LDG-1 다음 1",
            "- LDG-2 다음 2",
            "- LDG-3 다음 3",
            "- LDG-4 다음 4",
            "- LDG-5 다음 5",
            "다른 세션에서 작업중:",
            "- LDG-7 다른 작업 (sess·0the, 최근 활동)",
            "직전 세션 메모 (LDG-7 다른 작업):",
            "  승인금액 케이스 남음",
            SessionContext.skillHint,
        ])
        #expect(!text.contains("LDG-6"))
    }

    /// 직전 세션 메모는 가장 최근에 handoff한 카드 하나. 나중에 다른 이유로 고친 카드(updatedAt)가 앞서지 않는다.
    /// 완료된 카드의 메모는 뺀다.
    @Test func latestHandoffWins() throws {
        let h = try HookHarness()
        let p = h.project
        let older = p.makeCard(in: h.context, title: "옛 카드", status: .next, at: t0)
        let newer = p.makeCard(in: h.context, title: "새 카드", status: .idea, at: t0)
        let done = p.makeCard(in: h.context, title: "끝난 카드", status: .done, at: t0)
        try h.context.save()
        let tools = MCPTools(context: h.context, now: { t0 + 10 })
        _ = try tools.call("card_handoff", ["id": "LDG-1", "nextSessionNote": "옛 메모"])
        let later = MCPTools(context: h.context, now: { t0 + 20 })
        _ = try later.call("card_handoff", ["id": "LDG-2", "nextSessionNote": "여기까지 함\n남은 것: 테스트"])
        let latest = MCPTools(context: h.context, now: { t0 + 30 })
        _ = try latest.call("card_handoff", ["id": "LDG-3", "nextSessionNote": "끝난 카드 메모"])
        older.updatedAt = t0 + 40 // 메모와 상관없는 수정
        #expect(done.status == .done)

        let text = try #require(try h.send("doc-SessionStart", at: t0 + 60))
        #expect(text.contains("직전 세션 메모 (LDG-2 새 카드):\n  여기까지 함\n  남은 것: 테스트\n"))
        #expect(!text.contains("옛 메모"))
        #expect(!text.contains("끝난 카드 메모"))
        #expect(newer.status == .idea)
    }

    // 상황 글과 직전 세션 메모의 빈 줄은 블록에 싣지 않는다.
    @Test func blankLinesInStatusAndNoteAreDropped() throws {
        let h = try HookHarness()
        Event.record(.projectStatus, in: h.context, project: h.project, at: t0,
                     payload: ["summary": .string("파서 진행 중\n\n다음: 테스트")])
        let card = h.project.makeCard(in: h.context, title: "파서", status: .next, at: t0)
        card.nextSessionNote = "여기까지 함\n\n남은 것: 테스트"
        try h.context.save()
        let lines = try #require(try h.send("doc-SessionStart", at: t0 + 60)).components(separatedBy: "\n")
        #expect(lines.contains("  파서 진행 중") && lines.contains("  다음: 테스트"))
        #expect(lines.contains("  여기까지 함") && lines.contains("  남은 것: 테스트"))
        #expect(!lines.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // 자기 세션과 그 서브에이전트가 잡은 카드는 「다른 세션에서 작업중」에 넣지 않는다.
    @Test func ownAndSubagentCardsAreNotListedAsOthers() throws {
        let h = try HookHarness()
        let mine = h.project.makeCard(in: h.context, title: "내 작업", status: .next, at: t0)
        let delegated = h.project.makeCard(in: h.context, title: "맡긴 작업", status: .next, at: t0)
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-SubagentStart", at: t0 + 1)
        let main = try #require(try h.session())
        let sub = try #require(try h.session(HookHarness.agentID))
        CardLifecycle.attach(mine, main, at: t0 + 2, in: h.context)
        CardLifecycle.attach(delegated, sub, at: t0 + 2, in: h.context)
        #expect(!SessionContext.text(project: h.project, session: main, now: t0 + 10).contains("다른 세션에서 작업중"))
        // 다른 세션이 볼 때는 둘 다 나온다
        let other = makeSession(h.context, h.project, id: "0ther-session", startedAt: t0, lastSeenAt: t0)
        let seen = SessionContext.text(project: h.project, session: other, now: t0 + 10)
        #expect(seen.contains("- LDG-1 내 작업") && seen.contains("- LDG-2 맡긴 작업"))
    }

    // 넘긴 뒤에 카드에 다른 메모가 붙어도 직전 세션 메모는 가장 최근에 넘긴 카드 것이다.
    @Test func laterPlainNoteDoesNotCountAsHandoff() throws {
        let h = try HookHarness()
        let older = h.project.makeCard(in: h.context, title: "옛 카드", status: .next, at: t0)
        _ = h.project.makeCard(in: h.context, title: "새 카드", status: .next, at: t0)
        try h.context.save()
        _ = try MCPTools(context: h.context, now: { t0 + 10 }).call("card_handoff", ["id": "LDG-1", "nextSessionNote": "옛 메모"])
        _ = try MCPTools(context: h.context, now: { t0 + 20 }).call("card_handoff", ["id": "LDG-2", "nextSessionNote": "새 메모"])
        Event.record(.note, in: h.context, project: h.project, card: older, at: t0 + 30,
                     payload: ["kind": .string("user.prompt"), "text": .string("옛 카드 얘기")])
        let text = try #require(try h.send("doc-SessionStart", at: t0 + 60))
        #expect(text.contains("직전 세션 메모 (LDG-2 새 카드):\n  새 메모\n"))
    }

    @Test func minimalBlockWithoutCards() throws {
        let h = try HookHarness()
        let text = try #require(try h.send("doc-SessionStart", at: t0))
        #expect(text == "Waypoint: LDG (가계부 앱)\nsessionId: \(HookHarness.sessionID)\n\(SessionContext.skillHint)")
    }
}
