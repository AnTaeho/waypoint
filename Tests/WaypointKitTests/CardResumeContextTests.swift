import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct CardResumeContextTests {
    @Test func exportsRemainingWorkWithoutMutatingOrReusingOldSession() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "Resume target", status: .next, at: t0)
        card.body = "The goal"; card.nextSessionNote = "Start with validation"
        card.criteria = [Criterion("remaining"), Criterion("already satisfied", isDone: true)]
        let old = makeSession(h.context, h.project, id: "old-session-do-not-copy")
        CardLifecycle.attach(card, old, at: t0, in: h.context)
        CardLifecycle.detach(card, old, at: t0 + 1, in: h.context)
        let before = try h.context.fetchCount(FetchDescriptor<Event>())
        let text = try #require(CardResumeContext.text(card: card, provider: .codex))
        #expect(text.contains("The goal") && text.contains("Start with validation"))
        #expect(text.contains("- remaining") && text.contains("[체크됨] already satisfied · 미검증"))
        #expect(text.contains("provider: codex") && text.contains("codex:"))
        #expect(text.contains("session_bind") && text.contains("card_get") && text.contains("card_start"))
        #expect(!text.contains(old.id))
        #expect(card.status == .next && card.openCardSessions.isEmpty)
        #expect(try h.context.fetchCount(FetchDescriptor<Event>()) == before)
        let claude = try #require(CardResumeContext.text(card: card, provider: .claude))
        #expect(claude.contains("provider: claude") && claude.contains("tracker 스킬"))
        #expect(!claude.contains("CODEX_SESSION_ID"))
    }

    @Test func filesAreDeduplicatedRecentAndScopedToCard() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "target", status: .next, at: t0)
        for second in 0..<12 {
            Event.record(.fileChanged, in: h.context, card: card, at: t0 + Double(second), payload: ["path": .string("file\(second).swift")])
        }
        Event.record(.fileChanged, in: h.context, card: card, at: t0 + 20, payload: ["path": "file0.swift"])
        let other = h.project.makeCard(in: h.context, title: "other", status: .next, at: t0)
        Event.record(.fileChanged, in: h.context, card: other, at: t0 + 30, payload: ["path": "other-secret.swift"])
        Event.record(.commit, in: h.context, card: card, at: t0, payload: ["hash": "123456789012345", "message": "checkpoint"])
        let files = CardResumeContext.recentFiles(card)
        #expect(files.count == 12 && files.first == "file0.swift")
        let text = try #require(CardResumeContext.text(card: card, provider: .codex))
        #expect(text.contains("외 2개") && text.contains("123456789012 checkpoint"))
        #expect(!text.contains("other-secret.swift"))
    }

    @Test func exportsEvidenceIndependentlyOfCheckboxAndRefreshesAfterChanges() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "evidence", status: .next, at: t0)
        card.criteria = [Criterion("checked without evidence", isDone: true),
                         Criterion("reported pass"), Criterion("confirmed failure", isDone: true),
                         Criterion("skipped")]
        for (index, outcome) in [(1, CheckOutcome.pass), (2, .fail), (3, .skipped)] {
            CardEvidence.record(CheckRecord(at: t0, command: "swift test --filter Case\(index)",
                outcome: outcome, source: .agent, criterion: index, criterionText: card.criteria[index].text),
                card: card, session: nil, in: h.context)
        }
        CardEvidence.record(CheckRecord(at: t0, command: "swift test --filter Case2", outcome: .fail,
            source: .hook), card: card, session: nil, in: h.context)
        for provider in AgentProvider.allCases {
            let text = try #require(CardResumeContext.text(card: card, provider: provider))
            #expect(text.contains("[체크됨] checked without evidence · 미검증"))
            #expect(text.contains("[미체크] reported pass · 통과 · 보고"))
            #expect(text.contains("[체크됨] confirmed failure · 실패 · 확인됨"))
            #expect(text.contains("skipped · 건너뜀 · 보고"))
        }
        Event.record(.fileChanged, in: h.context, card: card, at: t0 + 1, payload: ["path": "edited.swift"])
        let changed = try #require(CardResumeContext.text(card: card, provider: .codex))
        #expect(changed.contains("reported pass · 변경 후 미검증 · 보고"))
        #expect(changed.contains("confirmed failure · 변경 후 미검증 · 확인됨"))
        #expect(card.criteria[0].isDone && !card.criteria[1].isDone && card.status == .next)
    }

    @Test func evidenceListIsBoundedAndKeepsOriginalCriterionNumbers() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "many", status: .next, at: t0)
        card.criteria = (1...22).map { Criterion("item\($0)", isDone: true) }
        let text = try #require(CardResumeContext.text(card: card, provider: .codex))
        #expect(text.contains("조건 20 [체크됨] item20 · 미검증"))
        #expect(!text.contains("item21"))
        #expect(text.contains("외 2개 — card_get에서 전체 검증 상태 확인"))
    }

    @Test func unavailableAndEmptyStatesAreExplicit() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "empty", status: .next, at: t0)
        let text = try #require(CardResumeContext.text(card: card, provider: .claude))
        #expect(text.contains("등록된 메모 없음") && text.contains("기록된 파일 없음"))
        card.body = String(repeating: "가", count: 7000)
        #expect(CardResumeContext.text(card: card, provider: .claude)?.contains("일부 생략") == true)
        for (status, reason) in [(CardStatus.done, "완료한 카드"), (.archived, "보관한 카드")] {
            card.status = status
            #expect(CardResumeContext.text(card: card, provider: .claude) == nil)
            #expect(CardResumeContext.unavailableReason(card) == reason)
        }
        card.status = .next; h.project.archivedAt = t0
        #expect(CardResumeContext.text(card: card, provider: .claude) == nil)
        #expect(CardResumeContext.unavailableReason(card) == "보관한 프로젝트")
        h.project.archivedAt = nil; h.project.rootPath = " "
        #expect(CardResumeContext.text(card: card, provider: .claude) == nil)
        #expect(CardResumeContext.unavailableReason(card) == "작업 폴더 없음")
        card.project = nil
        #expect(CardResumeContext.text(card: card, provider: .claude) == nil)
        #expect(CardResumeContext.unavailableReason(card) == "프로젝트 없음")
    }

    @Test func newProviderSessionResumesSameCardFromDifferentFolder() throws {
        for provider in AgentProvider.allCases {
            let h = try HookHarness()
            let card = h.project.makeCard(in: h.context, title: "resume", status: .next, at: t0)
            let old = makeSession(h.context, h.project, id: "previous")
            CardLifecycle.attach(card, old, at: t0, in: h.context)
            CardLifecycle.detach(card, old, at: t0 + 1, in: h.context)
            let attempt = CardResumeAttempt(card: card, provider: provider, at: t0 + 2)
            #expect(attempt.state(for: card) == .waiting)
            let tools = MCPTools(context: h.context, now: { t0 + 10 })
            let id = provider == .codex ? "codex:new-real-session" : "new-real-session"
            #expect(CardResumeContext.text(card: card, provider: provider) != nil)
            _ = try tools.call("session_bind", ["project": "LDG", "sessionId": .string(id),
                                                "provider": .string(provider.rawValue), "cwd": "/workspace"])
            let latest = try tools.call("card_get", ["id": .string(card.displayID)])
            #expect(latest["status"] == "next")
            _ = try tools.call("card_start", ["id": .string(card.displayID), "sessionId": .string(id)])
            #expect(attempt.state(for: card) == .connected)
            #expect(card.status == .active && card.openCardSessions.count == 1)
            #expect(card.openCardSessions.first?.session?.id == id)
            #expect(card.cardSessions?.count == 2)
            #expect(old.openCardSessions.isEmpty)
        }
    }

    // Codex에는 waypoint-tracker, Claude에는 tracker 스킬을 안내한다.
    @Test func namesTheSkillOfTheChosenTool() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "skill", status: .next, at: t0)
        let codex = try #require(CardResumeContext.text(card: card, provider: .codex))
        let claude = try #require(CardResumeContext.text(card: card, provider: .claude))
        #expect(codex.contains("먼저 waypoint-tracker 스킬을"))
        #expect(claude.contains("먼저 tracker 스킬을") && !claude.contains("waypoint-tracker"))
    }

    // 딱 한도만큼이면 「외 0개」나 생략 표시를 붙이지 않는다.
    @Test func exactLimitsAddNoOverflowLines() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "limits", status: .next, at: t0)
        card.body = String(repeating: "가", count: 6000)
        card.criteria = (1...20).map { Criterion("item\($0)") }
        for index in 1...10 {
            Event.record(.fileChanged, in: h.context, card: card, at: t0 + Double(index), payload: ["path": .string("file\(index).swift")])
        }
        let text = try #require(CardResumeContext.text(card: card, provider: .claude))
        #expect(text.contains("- item20") && text.contains("조건 20 [미체크] item20") && text.contains("- file1.swift"))
        #expect(!text.contains("외 0개"))
        #expect(!text.contains("일부 생략"))
    }

    // 다른 프로젝트 이름으로 남은 이 카드의 기록은 재개 문맥에 넣지 않는다.
    @Test func recordsFiledUnderAnotherProjectAreLeftOut() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "scoped", status: .next, at: t0)
        let other = makeProject(h.context, key: "OTH")
        Event.record(.fileChanged, in: h.context, project: other, card: card, at: t0, payload: ["path": "elsewhere.swift"])
        Event.record(.fileChanged, in: h.context, card: card, at: t0 + 1, payload: ["path": "here.swift"])
        #expect(CardResumeContext.recentFiles(card) == ["here.swift"])
    }
}
