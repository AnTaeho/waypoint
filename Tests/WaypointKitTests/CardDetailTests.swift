import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct CardEditingTests {
    @Test func toggleCriterionRecordsNoteAndSaves() throws {
        let (container, ctx) = try makeContext()
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next,
                              criteria: [Criterion("하나"), Criterion("둘", isDone: true)], at: t0)
        #expect(CardEditing.setCriterion(card, at: 0, isDone: true, date: t0 + 60, in: ctx))
        #expect(card.doneCriteriaCount == 2)
        #expect(card.updatedAt == t0 + 60)
        let notes = events(card, .note)
        #expect(notes.count == 1)
        #expect(notes.first?.payloadValues["kind"]?.stringValue == CardEditing.criterionNoteKind)
        #expect(notes.first?.payloadValues["text"]?.stringValue == "하나")
        #expect(notes.first?.payloadValues["isDone"]?.boolValue == true)
        try ctx.save()

        let fresh = ModelContext(container)
        let id = card.id
        let reread = try #require(try fresh.fetch(FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.id == id })).first)
        #expect(reread.criteria.map(\.isDone) == [true, true])
    }

    @Test func sameValueOrOutOfRangeIsNoop() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", criteria: [Criterion("하나", isDone: true)], at: t0)
        #expect(CardEditing.setCriterion(card, at: 0, isDone: true, date: t0 + 1, in: ctx) == false)
        #expect(CardEditing.setCriterion(card, at: 3, isDone: true, date: t0 + 1, in: ctx) == false)
        #expect(CardEditing.setCriterion(card, at: -1, isDone: false, date: t0 + 1, in: ctx) == false)
        #expect(events(card, .note).isEmpty)
        #expect(card.updatedAt == t0)
    }

    @Test func criterionChangeDoesNotChangeStatus() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, criteria: [Criterion("하나")], at: t0)
        CardEditing.setCriterion(card, at: 0, isDone: true, date: t0 + 1, in: ctx)
        // 조건을 다 채워도 자동으로 done이 되지 않는다
        #expect(card.status == .next)
        #expect(card.doneAt == nil)
    }
}

@Suite struct CardHistoryFormatTests {
    @Test func linesNewestFirst() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", status: .next, criteria: [Criterion("가맹점명")], at: t0)
        Event.record(.cardCreated, in: ctx, card: card, at: t0, payload: ["status": "next"])
        let s = makeSession(ctx, p, id: "7f2a9c41")
        CardLifecycle.attach(card, s, at: t0 + 10, in: ctx)
        Event.record(.fileChanged, in: ctx, card: card, session: s, at: t0 + 20,
                     payload: ["path": "Ledger/OCR/ReceiptParser.swift", "added": 84, "removed": 12])
        Event.record(.commit, in: ctx, card: card, session: s, at: t0 + 30,
                     payload: ["hash": "4c1d9e0aa", "message": "파서 추가"])
        CardEditing.setCriterion(card, at: 0, isDone: true, date: t0 + 40, in: ctx)
        Event.record(.note, in: ctx, card: card, at: t0 + 50, payload: ["text": "메모 한 줄"])
        Event.record(.sessionStart, in: ctx, project: p, card: card, session: s, at: t0 + 60)

        let lines = CardHistoryFormat.lines(for: card)
        // attach는 연결·상태 이벤트를 같은 시각에 남기므로 그 두 줄의 순서는 정하지 않는다.
        let texts = lines.map(\.text)
        try #require(texts.count == 7)
        #expect(Array(texts.prefix(4)) == ["메모 한 줄", "완료 조건 체크 · 가맹점명", "커밋 · 파서 추가", "파일 변경 +84 −12"])
        #expect(Set(texts[4...5]) == ["다음 할 일 → 작업중", "세션 연결"])
        #expect(texts.last == "카드 생성 · 다음 할 일")
        #expect(lines.first { $0.marker == .commit }?.code == "4c1d9e0")
        #expect(lines.first { $0.marker == .file }?.code == "ReceiptParser.swift")
        #expect(lines.first { $0.marker == .file }?.session == "sess·7f2a")
        #expect(lines.last?.marker == .next)
    }

    @Test func changedFilesAreSummedPerPath() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let p = makeProject(ctx)
        let card = p.makeCard(in: ctx, title: "a", at: t0)
        Event.record(.fileChanged, in: ctx, card: card, at: t0 + 1, payload: ["path": "A.swift", "added": 3, "removed": 1])
        Event.record(.fileChanged, in: ctx, card: card, at: t0 + 2, payload: ["path": "B.swift", "added": 5, "removed": 0])
        Event.record(.fileChanged, in: ctx, card: card, at: t0 + 3, payload: ["path": "A.swift", "added": 2, "removed": 2])
        Event.record(.fileChanged, in: ctx, card: card, at: t0 + 4, payload: ["path": ""])
        let files = CardHistoryFormat.changedFiles(for: card)
        #expect(files.map(\.path) == ["A.swift", "B.swift"])
        #expect(files.first?.added == 5)
        #expect(files.first?.removed == 3)
    }

    @Test func sampleCardFilesMatchDesign() throws {
        let (_c, ctx) = try makeContext(); _ = _c
        let now = t0 + 7 * 24 * 3600
        try SampleData.seedIfEmpty(ctx, now: now)
        let ldg = try #require(try ctx.fetch(FetchDescriptor<Project>()).first { $0.key == "LDG" })
        let c14 = try #require(ldg.cards?.first { $0.number == 14 })
        let files = CardHistoryFormat.changedFiles(for: c14)
        #expect(Set(files.map(\.path)) == ["Ledger/OCR/ReceiptParser.swift", "Ledger/Models/Transaction.swift"])
        let parser = try #require(files.first { $0.path.hasSuffix("ReceiptParser.swift") })
        #expect(parser.added == 84)
        #expect(parser.removed == 12)
    }
}
