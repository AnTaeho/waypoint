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
}
