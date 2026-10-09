import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct ProjectActivityTests {
    @Test func delayedPromptKeepsHistoricalProjectAndCardWithoutDuplicating() throws {
        let h = try HookHarness()
        let sender = LastPromptTests()
        try h.send("doc-SessionStart", at: t0)
        let session = try #require(try h.session())
        let card = h.project.makeCard(in: h.context, title: "original", status: .next, at: t0)
        CardLifecycle.attach(card, session, at: t0 + 1, in: h.context)
        let other = makeProject(h.context, key: "NEW")
        SessionProjectBinding.bind(session, to: other, at: t0 + 100, in: h.context)
        try sender.send(h, at: t0 + 120, override: ["prompt": "new request"])
        for _ in 0..<2 { try sender.send(h, at: t0 + 10, override: ["prompt": "old request"]) }
        let prompts = (session.events ?? []).filter { $0.payloadValues["kind"] == "user.prompt" }
        #expect(prompts.count == 2)
        let old = try #require(prompts.first { $0.payloadValues["text"] == "old request" })
        #expect(old.project === h.project && old.card === card)
        #expect(prompts.first { $0.payloadValues["text"] == "new request" }?.project === other)
        #expect(session.lastPrompt == "new request")
        let days = ProjectActivity.days(events: prompts, projectID: h.project.id)
        #expect(days.flatMap(\.groups).flatMap(\.entries).map(\.text) == ["old request"])
    }

    @Test func coalescesOnlyAdjacentFileChangesWithinFiveMinutes() throws {
        let h = try HookHarness()
        let s = makeSession(h.context, h.project, id: "s")
        var events: [Event] = []
        for second in [0.0, 10, 20, 40, 400] {
            events.append(Event.record(.fileChanged, in: h.context, session: s, at: t0 + second,
                                       payload: ["path": "a.swift", "added": 2, "removed": 1]))
        }
        events.append(Event.record(.note, in: h.context, session: s, at: t0 + 30, payload: ["text": "boundary"]))
        let entries = ProjectActivity.days(events: events, projectID: h.project.id).flatMap(\.groups).flatMap(\.entries)
        #expect(entries.map(\.count) == [1, 1, 1, 3])
        #expect(entries.last?.added == 6 && entries.last?.removed == 3)
    }

    @Test func filtersProviderCardSessionAndSearchWithManualRecords() throws {
        let h = try HookHarness()
        let s = makeSession(h.context, h.project, id: "codex:s"); s.provider = .codex
        let card = h.project.makeCard(in: h.context, title: "Searchable card", status: .next, at: t0)
        let events = [
            Event.record(.commit, in: h.context, card: card, session: s, at: t0, payload: ["message": "fix", "hash": "abc"]),
            Event.record(.note, in: h.context, card: card, at: t0 + 1, payload: ["kind": "handoff", "text": "continue"]),
            Event.record(.cardStatus, in: h.context, card: card, at: t0 + 2, payload: ["to": "done"])
        ]
        var filter = ActivityFilter(); filter.provider = "codex"; filter.card = card.id.uuidString; filter.session = s.id
        let groups = ProjectActivity.days(events: events, projectID: h.project.id, filter: filter, search: "searchable").flatMap(\.groups)
        #expect(groups.count == 1 && groups.first?.entries.first?.type == .commit)
        filter = ActivityFilter(); filter.provider = "none"
        let manual = ProjectActivity.days(events: events, projectID: h.project.id, filter: filter).flatMap(\.groups)
        #expect(manual.first?.session == nil)
        #expect(manual.first?.entries.map(\.kind) == ["done", "handoff"])
        #expect(manual.first?.entries.last?.card === card)
    }

    @Test func datesUseCalendarAndSortNewestFirst() throws {
        let h = try HookHarness()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let events = [0.0, 86400].map {
            Event.record(.note, in: h.context, project: h.project, at: t0 + $0, payload: ["text": "day"])
        }
        let days = ProjectActivity.days(events: events, projectID: h.project.id, calendar: calendar)
        #expect(days.count == 2 && days[0].id > days[1].id)
    }

    // 필터는 한 칸이라도 「전체」가 아니면 켜진 것이다.
    @Test func filterIsActiveWhenAnySingleFieldIsNarrowed() {
        #expect(!ActivityFilter().isActive)
        var filter = ActivityFilter(); filter.provider = "codex"
        #expect(filter.isActive)
        filter = ActivityFilter(); filter.card = "none"
        #expect(filter.isActive)
        filter = ActivityFilter(); filter.session = "s"
        #expect(filter.isActive)
    }

    // 묶음 제목은 문장이 남은 요청이고, 요약은 0인 항목을 빼고 센다.
    @Test func groupTitleUsesPromptAndSummaryOmitsZeroCounts() throws {
        let h = try HookHarness()
        let s = makeSession(h.context, h.project, id: "s")
        let card = h.project.makeCard(in: h.context, title: "card", status: .next, at: t0)
        let worked = [
            Event.record(.note, in: h.context, session: s, at: t0, payload: ["kind": "user.prompt", "text": "fix the parser"]),
            Event.record(.fileChanged, in: h.context, session: s, at: t0 + 1, payload: ["path": "a.swift"]),
            Event.record(.fileChanged, in: h.context, session: s, at: t0 + 2, payload: ["path": "b.swift"]),
            Event.record(.commit, in: h.context, session: s, at: t0 + 3, payload: ["message": "fix", "hash": "abc"]),
            Event.record(.cardStatus, in: h.context, card: card, session: s, at: t0 + 4, payload: ["to": "done"]),
        ]
        let group = try #require(ProjectActivity.days(events: worked, projectID: h.project.id).first?.groups.first)
        #expect(group.title == "fix the parser")
        #expect(group.summary == "파일 2개 · 커밋 1개 · 완료 1건 · 기록 5건")
        let memo = [Event.record(.note, in: h.context, project: h.project, at: t0 + 10, payload: ["text": "memo"])]
        let manual = try #require(ProjectActivity.days(events: memo, projectID: h.project.id).first?.groups.first)
        #expect(manual.title == "카드·프로젝트 기록")
        #expect(manual.summary == "기록 1건")
    }

    // 카드·세션 필터는 맞지 않는 기록을 뺀다.
    @Test func cardAndSessionFiltersDropNonMatchingRecords() throws {
        let h = try HookHarness()
        let a = makeSession(h.context, h.project, id: "a"), b = makeSession(h.context, h.project, id: "b")
        let mine = h.project.makeCard(in: h.context, title: "mine", status: .next, at: t0)
        let other = h.project.makeCard(in: h.context, title: "other", status: .next, at: t0)
        let events = [
            Event.record(.note, in: h.context, card: mine, session: a, at: t0, payload: ["text": "mine by a"]),
            Event.record(.note, in: h.context, card: other, session: b, at: t0 + 1, payload: ["text": "other by b"]),
            Event.record(.note, in: h.context, project: h.project, at: t0 + 2, payload: ["text": "manual"]),
        ]
        func texts(_ filter: ActivityFilter) -> [String] {
            ProjectActivity.days(events: events, projectID: h.project.id, filter: filter)
                .flatMap(\.groups).flatMap(\.entries).map(\.text)
        }
        var filter = ActivityFilter(); filter.card = mine.id.uuidString
        #expect(texts(filter) == ["mine by a"])
        filter = ActivityFilter(); filter.session = "b"
        #expect(texts(filter) == ["other by b"])
    }

    // 세션 묶음은 최근 기록이 있는 쪽이 먼저, 같은 시각이면 묶음 ID순.
    @Test func sessionGroupsSortByLatestRecordThenID() throws {
        let h = try HookHarness()
        let a = makeSession(h.context, h.project, id: "a"), b = makeSession(h.context, h.project, id: "b")
        func ids(_ events: [Event]) -> [String?] {
            ProjectActivity.days(events: events, projectID: h.project.id).flatMap(\.groups).map(\.session?.id)
        }
        let apart = [Event.record(.note, in: h.context, session: a, at: t0, payload: ["text": "older"]),
                     Event.record(.note, in: h.context, session: b, at: t0 + 60, payload: ["text": "newer"])]
        #expect(ids(apart) == ["b", "a"])
        let tied = [Event.record(.note, in: h.context, session: b, at: t0 + 120, payload: ["text": "b"]),
                    Event.record(.note, in: h.context, session: a, at: t0 + 120, payload: ["text": "a"])]
        #expect(ids(tied) == ["a", "b"])
    }

    // 딱 5분 간격의 같은 파일 변경은 한 줄로 묶인다.
    @Test func fileChangesExactlyFiveMinutesApartCoalesce() throws {
        let h = try HookHarness()
        let s = makeSession(h.context, h.project, id: "s")
        let events = [0.0, 300, 601].map {
            Event.record(.fileChanged, in: h.context, session: s, at: t0 + $0, payload: ["path": "a.swift", "added": 1, "removed": 0])
        }
        let entries = ProjectActivity.days(events: events, projectID: h.project.id).flatMap(\.groups).flatMap(\.entries)
        #expect(entries.map(\.count) == [1, 2])
    }
}
