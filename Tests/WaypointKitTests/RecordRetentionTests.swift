import Foundation
import SwiftData
import Testing
@testable import WaypointKit

private let day: TimeInterval = 24 * 60 * 60

/// 기록 보관 14일(`RecordRetention`, SPEC 5장 「기록 보관」). `now`는 t0 + 30일, 기준 시각은 t0 + 16일.
@Suite struct RecordRetentionTests {
    let now = t0 + 30 * day
    var cutoff: Date { now - 14 * day }

    // MARK: - 판정

    @Test func expiresAtExactlyFourteenDays() {
        #expect(RecordRetention.days == 14)
        #expect(!RecordRetention.isExpired(at: t0, now: t0 + 14 * day - 1))
        #expect(RecordRetention.isExpired(at: t0, now: t0 + 14 * day))
        #expect(RecordRetention.isExpired(at: t0, now: t0 + 14 * day + 1))
    }

    @Test func runsOnStartThenDailyAndSoonerWhenUnfinished() {
        #expect(RecordRetention.isDue(lastRun: nil, unfinished: false, now: t0))
        #expect(RecordRetention.isDue(lastRun: nil, unfinished: true, now: t0))
        #expect(!RecordRetention.isDue(lastRun: t0, unfinished: false, now: t0 + day - 1))
        #expect(RecordRetention.isDue(lastRun: t0, unfinished: false, now: t0 + day))
        #expect(!RecordRetention.isDue(lastRun: t0, unfinished: true, now: t0 + 59))
        #expect(RecordRetention.isDue(lastRun: t0, unfinished: true, now: t0 + 60))
    }

    private func expires(_ type: EventType, kind: String? = nil, card: Bool = false, latest: Bool = false,
                         at: Date? = nil) -> Bool {
        RecordRetention.expires(type: type, kind: kind, hasCard: card, isLatest: latest, at: at ?? t0, now: now)
    }

    @Test func eventRuleByType() {
        // 카드에 이어졌든 아니든 지우는 것
        for type in [EventType.guideSynced, .cardAttached, .cardDetached] {
            #expect(expires(type) && expires(type, card: true) && expires(type, card: true, latest: true))
        }
        // 요청만 지우고 다른 메모는 남긴다
        #expect(expires(.note, kind: "user.prompt") && expires(.note, kind: "user.prompt", card: true))
        for kind in [nil, "handoff", "criterion", "project.bound"] as [String?] {
            #expect(!expires(.note, kind: kind) && !expires(.note, kind: kind, card: true))
        }
        // 검증·커밋은 카드에 이어진 것만 남긴다
        for type in [EventType.check, .commit] {
            #expect(expires(type) && expires(type, latest: true))
            #expect(!expires(type, card: true))
        }
        // 파일 변경은 카드의 가장 최근 것만 남긴다
        #expect(expires(.fileChanged) && expires(.fileChanged, card: true) && expires(.fileChanged, latest: true))
        #expect(!expires(.fileChanged, card: true, latest: true))
        // 지금 상황은 프로젝트의 가장 최근 것만 남긴다
        #expect(expires(.projectStatus) && expires(.projectStatus, card: true))
        #expect(!expires(.projectStatus, latest: true))
        // 날짜와 상관없이 남기는 것
        for type in [EventType.cardCreated, .cardStatus, .sessionStart, .sessionEnd, .sessionFiled, .githubIssue, .githubPR] {
            #expect(!expires(type) && !expires(type, card: true))
        }
    }

    @Test func nothingExpiresBeforeFourteenDays() {
        for type in EventType.allCases {
            #expect(!expires(type, kind: "user.prompt", at: cutoff + 1))
            #expect(!expires(type, kind: "user.prompt", card: true, at: cutoff + 1))
        }
        #expect(expires(.guideSynced, at: cutoff))
    }

    @Test func eventsThatGoWithTheirSession() {
        for type in [EventType.sessionStart, .sessionEnd, .sessionFiled] {
            #expect(RecordRetention.goesWithSession(type: type, kind: nil))
        }
        #expect(RecordRetention.goesWithSession(type: .note, kind: "user.prompt"))
        #expect(RecordRetention.goesWithSession(type: .note, kind: "project.bound"))
        #expect(!RecordRetention.goesWithSession(type: .note, kind: nil))
        #expect(!RecordRetention.goesWithSession(type: .note, kind: "handoff"))
        for type in [EventType.projectStatus, .githubIssue, .githubPR, .cardCreated, .check, .commit, .fileChanged] {
            #expect(!RecordRetention.goesWithSession(type: type, kind: "user.prompt"))
        }
    }

    private func facts(ended: Date?, seen: Date? = nil, linked: Bool = false) -> RecordRetention.SessionFacts {
        .init(endedAt: ended, lastSeenAt: seen ?? ended ?? t0, hasCardLink: linked)
    }

    @Test func sessionFamilyRule() {
        let old = facts(ended: cutoff)
        #expect(RecordRetention.familyExpires([old], now: now))
        #expect(RecordRetention.familyExpires([old, facts(ended: cutoff - day)], now: now))
        #expect(!RecordRetention.familyExpires([], now: now))
        // 끝나지 않았거나, 끝난 지 14일이 안 됐거나, 그 뒤에 활동이 있었으면 남긴다
        #expect(!RecordRetention.familyExpires([facts(ended: nil)], now: now))
        #expect(!RecordRetention.familyExpires([facts(ended: cutoff + 1)], now: now))
        #expect(!RecordRetention.familyExpires([facts(ended: cutoff, seen: cutoff + 1)], now: now))
        #expect(!RecordRetention.familyExpires([facts(ended: cutoff + 1, seen: cutoff)], now: now))
        // 카드에 이어졌으면 남긴다
        #expect(!RecordRetention.familyExpires([facts(ended: cutoff, linked: true)], now: now))
        // 하나라도 남아야 하면 묶음을 남긴다
        #expect(!RecordRetention.familyExpires([old, facts(ended: cutoff, linked: true)], now: now))
        #expect(!RecordRetention.familyExpires([facts(ended: nil), old], now: now))
        #expect(!RecordRetention.familyExpires([old, facts(ended: cutoff + 1)], now: now))
    }

    @Test func guideVersionRule() {
        #expect(RecordRetention.versionExpires(at: cutoff, isLatest: false, now: now))
        #expect(!RecordRetention.versionExpires(at: cutoff, isLatest: true, now: now))
        #expect(!RecordRetention.versionExpires(at: cutoff + 1, isLatest: false, now: now))
        #expect(!RecordRetention.versionExpires(at: cutoff + 1, isLatest: true, now: now))
    }

    // MARK: - 저장소

    private func count<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    private func left(_ ctx: ModelContext, _ type: EventType) -> [Event] {
        ProjectStatus.fetch(type, in: ctx).sorted { $0.at < $1.at }
    }

    @Test func deletesOldEventsByKind() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let card = project.makeCard(in: ctx, title: "카드", status: .done, at: t0)
        let session = makeSession(ctx, project, id: "open")
        let old = cutoff, recent = cutoff + 1
        for at in [old, recent] {
            Event.record(.guideSynced, in: ctx, project: project, at: at, payload: ["relPath": "CLAUDE.md"])
            Event.record(.cardAttached, in: ctx, card: card, session: session, at: at, payload: ["sessionId": "open"])
            Event.record(.cardDetached, in: ctx, card: card, session: session, at: at, payload: ["sessionId": "open"])
            Event.record(.note, in: ctx, project: project, card: card, session: session, at: at,
                         payload: ["kind": "user.prompt", "text": "요청"])
            Event.record(.note, in: ctx, card: card, at: at, payload: ["text": "메모"])
            Event.record(.note, in: ctx, card: card, at: at, payload: ["kind": "handoff", "text": "다음"])
            Event.record(.check, in: ctx, card: card, session: session, at: at, payload: ["command": "swift test"])
            Event.record(.check, in: ctx, project: project, session: session, at: at, payload: ["command": "swift test"])
            Event.record(.commit, in: ctx, card: card, at: at, payload: ["hash": "abc"])
            Event.record(.commit, in: ctx, project: project, at: at, payload: ["hash": "def"])
            Event.record(.fileChanged, in: ctx, project: project, session: session, at: at, payload: ["path": "a.swift"])
            Event.record(.cardStatus, in: ctx, card: card, at: at, payload: ["to": "done"])
            Event.record(.githubPR, in: ctx, project: project, at: at, payload: ["number": 1])
            Event.record(.sessionStart, in: ctx, project: project, session: session, at: at)
        }
        try ctx.save()

        let result = RecordRetention.apply(in: ctx, now: now)
        try ctx.save()
        // 지운 것: 지침 동기화, 연결, 해제, 요청, 카드 없는 검증·커밋·파일 변경
        #expect(result == .init(events: 7, sessions: 0, versions: 0, unfinished: false))
        for type in [EventType.guideSynced, .cardAttached, .cardDetached, .fileChanged] {
            #expect(left(ctx, type).map(\.at) == [recent])
        }
        let notes = left(ctx, .note).map { "\($0.payloadValues["kind"]?.stringValue ?? "memo")@\($0.at == old ? "old" : "new")" }
        #expect(notes.sorted() == ["handoff@new", "handoff@old", "memo@new", "memo@old", "user.prompt@new"])
        #expect(left(ctx, .check).filter { $0.card != nil }.count == 2)
        #expect(left(ctx, .check).filter { $0.card == nil }.map(\.at) == [recent])
        #expect(left(ctx, .commit).filter { $0.card == nil }.map(\.at) == [recent])
        #expect(left(ctx, .commit).filter { $0.card != nil }.count == 2)
        #expect(left(ctx, .cardStatus).count == 2 && left(ctx, .githubPR).count == 2 && left(ctx, .sessionStart).count == 2)
        #expect(count(Session.self, ctx) == 1 && count(Card.self, ctx) == 1)

        // 두 번째 정리는 지울 것이 없다
        let events = count(Event.self, ctx)
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
        #expect(count(Event.self, ctx) == events)
    }

    @Test func keepsLatestFileChangeOfEachCard() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let stale = project.makeCard(in: ctx, title: "오래된 카드", status: .done, at: t0)
        let busy = project.makeCard(in: ctx, title: "요즘 카드", status: .active, at: t0)
        let tied = project.makeCard(in: ctx, title: "같은 시각", status: .done, at: t0)
        func change(_ card: Card, _ path: String, at: Date) {
            Event.record(.fileChanged, in: ctx, card: card, at: at, payload: ["path": .string(path)])
        }
        change(stale, "a.swift", at: t0)
        change(stale, "b.swift", at: t0 + day)
        change(stale, "c.swift", at: t0 + 2 * day)
        change(busy, "d.swift", at: t0)
        change(busy, "e.swift", at: cutoff)
        change(busy, "f.swift", at: cutoff + 1)
        change(tied, "g.swift", at: t0)
        change(tied, "h.swift", at: t0 + day)
        change(tied, "i.swift", at: t0 + day)
        try ctx.save()

        #expect(RecordRetention.apply(in: ctx, now: now).events == 6)
        try ctx.save()
        func paths(_ card: Card) -> [String] {
            events(card, .fileChanged).compactMap { $0.payloadValues["path"]?.stringValue }.sorted()
        }
        #expect(paths(stale) == ["c.swift"])
        // 최근 변경이 있는 카드는 오래된 것을 모두 지운다
        #expect(paths(busy) == ["f.swift"])
        // 같은 시각이면 하나만 남기고, 다시 돌려도 그 하나가 남는다
        let survivor = events(tied, .fileChanged).map(\.id)
        #expect(survivor.count == 1 && events(tied, .fileChanged).first?.at == t0 + day)
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
        #expect(events(tied, .fileChanged).map(\.id) == survivor)
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
    }

    @Test func doneCardEvidenceLooksTheSameAfterCleanup() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        func card(_ title: String) -> Card {
            let card = project.makeCard(in: ctx, title: title, status: .done, at: t0)
            card.criteria = [Criterion("테스트 통과", isDone: true), Criterion("문서", isDone: true)]
            return card
        }
        func report(_ card: Card, _ index: Int, _ outcome: CheckOutcome, at: Date) {
            CardEvidence.record(CheckRecord(at: at, command: "swift test", outcome: outcome, source: .agent,
                                            criterion: index, criterionText: card.criteria[index].text),
                                card: card, session: nil, in: ctx)
        }
        func change(_ card: Card, at: Date) {
            Event.record(.fileChanged, in: ctx, card: card, at: at, payload: ["path": "a.swift"])
        }
        // 검증 뒤에 바뀐 것 없음 / 검증 뒤에 파일이 바뀜 / 두 조건 사이에 바뀜
        let clean = card("깨끗")
        change(clean, at: t0); change(clean, at: t0 + 60)
        report(clean, 0, .pass, at: t0 + 120); report(clean, 1, .pass, at: t0 + 130)
        let changed = card("바뀜")
        report(changed, 0, .pass, at: t0); report(changed, 1, .fail, at: t0 + 10)
        change(changed, at: t0 + 60); change(changed, at: t0 + 120)
        let between = card("사이")
        report(between, 0, .pass, at: t0)
        change(between, at: t0 + 60); change(between, at: t0 + 90)
        report(between, 1, .pass, at: t0 + 120)
        // 훅 기록(카드에 이어짐)이 보고를 확인한다
        Event.record(.check, in: ctx, card: clean, at: t0 + 100,
                     payload: ["command": "swift test", "outcome": "pass", "source": "hook"])
        try ctx.save()

        let cards = [clean, changed, between]
        let before = cards.map(CardEvidence.criteria)
        #expect(before[0].map(\.isStale) == [false, false] && before[0][0].source == .hook)
        #expect(before[1].map(\.isStale) == [true, true] && before[2].map(\.isStale) == [true, false])

        #expect(RecordRetention.apply(in: ctx, now: now).events == 3)
        try ctx.save()
        #expect(cards.map(CardEvidence.criteria) == before)
        #expect(cards.map { CardEvidence.records(for: $0).count } == [3, 2, 2])
    }

    @Test func keepsLatestStatusOfEachProject() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let ledger = makeProject(ctx)
        let other = makeProject(ctx, key: "OTH", name: "다른")
        func status(_ project: Project?, _ text: String, at: Date) {
            let event = Event.record(.projectStatus, in: ctx, project: project, at: at, payload: ["summary": .string(text)])
            if project == nil { event.project = nil }
        }
        status(ledger, "첫째", at: t0)
        status(ledger, "둘째", at: t0 + day)
        status(other, "옛것", at: t0)
        status(other, "경계", at: cutoff)
        status(other, "요즘", at: cutoff + 1)
        status(other, "지금", at: now - day)
        status(nil, "주인 없음", at: t0)
        try ctx.save()

        #expect(RecordRetention.apply(in: ctx, now: now).events == 4)
        try ctx.save()
        #expect(left(ctx, .projectStatus).compactMap { $0.payloadValues["summary"]?.stringValue } == ["둘째", "요즘", "지금"])
        #expect(ProjectStatus.latest(for: ledger)?.text == "둘째" && ProjectStatus.latest(for: other)?.text == "지금")
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
    }

    /// 끝난 세션 하나와 시작·끝 기록.
    @discardableResult
    private func ended(_ ctx: ModelContext, _ project: Project, _ id: String, at date: Date?, seen: Date? = nil,
                       parent: Session? = nil) -> Session {
        let session = makeSession(ctx, project, id: id, startedAt: t0, lastSeenAt: seen ?? date ?? t0, parent: parent)
        Event.record(.sessionStart, in: ctx, project: project, session: session, at: t0)
        if let date {
            session.endedAt = date
            Event.record(.sessionEnd, in: ctx, project: project, session: session, at: date, payload: ["reason": "exit"])
        }
        return session
    }

    private func sessionIDs(_ ctx: ModelContext) -> [String] {
        ((try? ctx.fetch(FetchDescriptor<Session>())) ?? []).map(\.id).sorted()
    }

    @Test func deletesEndedSessionsWithoutCardLink() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let card = project.makeCard(in: ctx, title: "카드", status: .done, at: t0)
        let gone = ended(ctx, project, "gone", at: cutoff)
        Event.record(.note, in: ctx, project: project, session: gone, at: t0, payload: ["kind": "project.bound", "to": "LDG"])
        Event.record(.sessionFiled, in: ctx, project: project, session: gone, at: now - day,
                     payload: ["sessionId": "gone", "outcome": "dismissed"])
        Event.record(.note, in: ctx, project: project, session: gone, at: now - day, payload: ["kind": "user.prompt", "text": "늦은 요청"])
        Event.record(.githubIssue, in: ctx, project: project, session: gone, at: t0, payload: ["number": 3])
        Event.record(.projectStatus, in: ctx, project: project, session: gone, at: t0, payload: ["summary": "상황"])
        let linked = ended(ctx, project, "linked", at: t0 + day)
        CardLifecycle.attach(card, linked, at: t0, in: ctx)
        CardLifecycle.detach(card, linked, at: t0 + day, in: ctx)
        // `work_file`로 카드에 넘긴 세션은 카드 연결 없이 기록만 카드에 이어진다
        let filed = ended(ctx, project, "filed", at: t0 + day)
        Event.record(.commit, in: ctx, project: project, card: card, session: filed, at: t0, payload: ["hash": "abc"])
        ended(ctx, project, "open", at: nil)
        ended(ctx, project, "recent", at: cutoff + 1)
        ended(ctx, project, "seen-later", at: cutoff, seen: cutoff + 1)
        ended(ctx, project, "ended-later", at: cutoff + 1, seen: cutoff)
        try ctx.save()

        let result = RecordRetention.apply(in: ctx, now: now)
        try ctx.save()
        // gone의 시작·끝·프로젝트 옮김·넘김·요청 + 14일 넘은 연결·해제 기록
        #expect(result.sessions == 1 && result.events == 7 && !result.unfinished)
        #expect(sessionIDs(ctx) == ["ended-later", "filed", "linked", "open", "recent", "seen-later"])
        #expect(left(ctx, .sessionStart).count == 6 && left(ctx, .sessionEnd).count == 5)
        #expect(left(ctx, .sessionStart).allSatisfy { $0.session != nil })
        #expect(left(ctx, .note).isEmpty && left(ctx, .sessionFiled).isEmpty)
        // 세션과 함께 가지 않는 기록은 세션 없이 남는다
        #expect(left(ctx, .githubIssue).map { $0.session == nil } == [true])
        #expect(left(ctx, .projectStatus).count == 1)
        // 카드의 누적 작업은 그대로
        #expect(count(CardSession.self, ctx) == 1)
        #expect(BoardQuery.stats(of: card).sessionCount == 1)
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
    }

    // 카드에 넘긴 기록이 이번에 모두 지워지는 세션은 같은 정리에서 같이 지운다.
    @Test func filedSessionGoesOnceItsCardRecordsGo() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let card = project.makeCard(in: ctx, title: "카드", status: .done, at: t0)
        let filed = ended(ctx, project, "filed", at: t0 + day)
        for i in 0..<2 {
            Event.record(.fileChanged, in: ctx, project: project, card: card, session: filed, at: t0 + Double(i),
                         payload: ["path": "a.swift"])
        }
        let later = ended(ctx, project, "later", at: nil)
        Event.record(.fileChanged, in: ctx, project: project, card: card, session: later, at: now - day, payload: ["path": "a.swift"])
        try ctx.save()

        let result = RecordRetention.apply(in: ctx, now: now)
        try ctx.save()
        // 옛 파일 변경 둘 + 세션의 시작·끝
        #expect(result == .init(events: 4, sessions: 1, versions: 0, unfinished: false))
        #expect(sessionIDs(ctx) == ["later"] && events(card, .fileChanged).count == 1)
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
    }

    @Test func parentAndSubagentsStayOrGoTogether() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let card = project.makeCard(in: ctx, title: "카드", status: .done, at: t0)
        // 둘 다 카드 없음 → 같이 지운다
        let lone = ended(ctx, project, "lone", at: cutoff)
        ended(ctx, project, "lone-sub", at: cutoff - 60, parent: lone)
        // 부모만 카드에 붙음 → 서브에이전트도 남긴다(누적 작업의 서브에이전트 수)
        let top = ended(ctx, project, "top", at: cutoff)
        ended(ctx, project, "top-sub", at: cutoff - 60, parent: top)
        CardLifecycle.attach(card, top, at: t0, in: ctx)
        // 서브에이전트만 카드에 붙음 → 부모도 남긴다
        let boss = ended(ctx, project, "boss", at: cutoff)
        let worker = ended(ctx, project, "boss-sub", at: cutoff - 60, parent: boss)
        CardLifecycle.attach(card, worker, at: t0, in: ctx)
        // 서브에이전트가 카드에 이어진 기록을 남김 → 묶음을 남긴다
        let writer = ended(ctx, project, "writer", at: cutoff)
        let helper = ended(ctx, project, "writer-sub", at: cutoff - 60, parent: writer)
        Event.record(.check, in: ctx, card: card, session: helper, at: t0, payload: ["command": "swift test"])
        // 서브에이전트가 끝나지 않았거나 최근에 끝남 → 묶음을 남긴다
        let waiting = ended(ctx, project, "waiting", at: cutoff)
        ended(ctx, project, "waiting-sub", at: nil, parent: waiting)
        let late = ended(ctx, project, "late", at: cutoff)
        ended(ctx, project, "late-sub", at: cutoff + 1, parent: late)
        // 부모를 잃은 서브에이전트는 혼자 판단한다
        let orphan = ended(ctx, project, "orphan-sub", at: cutoff, parent: lone)
        orphan.parent = nil
        try ctx.save()

        let result = RecordRetention.apply(in: ctx, now: now)
        try ctx.save()
        #expect(result.sessions == 3 && result.events == 6 + 2)
        #expect(sessionIDs(ctx) == ["boss", "boss-sub", "late", "late-sub", "top", "top-sub", "waiting", "waiting-sub",
                                    "writer", "writer-sub"])
        #expect(((try? ctx.fetch(FetchDescriptor<Session>())) ?? []).filter { $0.kind == .subagent }.allSatisfy { $0.parent != nil })
        #expect(BoardQuery.stats(of: card).subagentCount == 2)
        #expect(left(ctx, .sessionStart).count == 10 && left(ctx, .sessionStart).allSatisfy { $0.session != nil })
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
    }

    @Test func keepsLatestVersionOfEachGuideDoc() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        func doc(_ path: String, _ versions: [(String, Date)]) -> GuideDoc {
            let doc = GuideDoc(relPath: path, content: versions.last?.0 ?? "")
            ctx.insert(doc)
            doc.project = project
            for (content, at) in versions {
                let version = GuideVersion(content: content, at: at, source: .local)
                ctx.insert(version)
                version.doc = doc
            }
            return doc
        }
        let quiet = doc("CLAUDE.md", [("1", t0), ("2", t0 + day), ("3", t0 + 2 * day)])
        let busy = doc("AGENTS.md", [("a", t0), ("b", cutoff), ("c", cutoff + 1), ("d", now - day)])
        let orphan = GuideVersion(content: "주인 없음", at: t0, source: .app)
        ctx.insert(orphan)
        try ctx.save()

        let result = RecordRetention.apply(in: ctx, now: now)
        try ctx.save()
        #expect(result == .init(events: 0, sessions: 0, versions: 5, unfinished: false))
        #expect(GuideLibrary.versions(of: quiet).map(\.content) == ["3"])
        #expect(GuideLibrary.versions(of: busy).map(\.content) == ["d", "c"])
        #expect(count(GuideVersion.self, ctx) == 3 && count(GuideDoc.self, ctx) == 2)
        #expect(RecordRetention.apply(in: ctx, now: now) == .init())
    }

    // MARK: - 상한

    private func seedSynced(_ ctx: ModelContext, _ n: Int) -> Project {
        let project = makeProject(ctx)
        for i in 0..<n {
            Event.record(.guideSynced, in: ctx, project: project, at: t0 + Double(i), payload: ["relPath": "CLAUDE.md"])
        }
        return project
    }

    @Test func continuesOnNextRunWhenOverTheLimit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = seedSynced(ctx, 7)
        try ctx.save()

        #expect(RecordRetention.batchLimit == 500)
        #expect(RecordRetention.apply(in: ctx, now: now, limit: 3) == .init(events: 3, sessions: 0, versions: 0, unfinished: true))
        try ctx.save()
        // 오래된 것부터 지운다
        #expect(left(ctx, .guideSynced).map(\.at) == (3..<7).map { t0 + Double($0) })
        #expect(RecordRetention.apply(in: ctx, now: now, limit: 3).events == 3)
        try ctx.save()
        #expect(RecordRetention.apply(in: ctx, now: now, limit: 3) == .init(events: 1, sessions: 0, versions: 0, unfinished: false))
        try ctx.save()
        #expect(count(Event.self, ctx) == 0)
    }

    @Test func exactlyAtTheLimitRunsOnceMoreAndFindsNothing() throws {
        let (container, ctx) = try makeContext()
        _ = container
        _ = seedSynced(ctx, 3)
        try ctx.save()

        #expect(RecordRetention.apply(in: ctx, now: now, limit: 4) == .init(events: 3, sessions: 0, versions: 0, unfinished: false))
        try ctx.save()
        _ = seedSynced(ctx, 3)
        try ctx.save()
        #expect(RecordRetention.apply(in: ctx, now: now, limit: 3) == .init(events: 3, sessions: 0, versions: 0, unfinished: true))
        try ctx.save()
        #expect(RecordRetention.apply(in: ctx, now: now, limit: 3) == .init())
    }

    @Test func limitCoversEveryKind() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        let card = project.makeCard(in: ctx, title: "카드", status: .done, at: t0)
        for i in 0..<2 {
            let at = t0 + Double(i)
            Event.record(.guideSynced, in: ctx, project: project, at: at, payload: ["relPath": "CLAUDE.md"])
            Event.record(.cardAttached, in: ctx, card: card, at: at, payload: ["sessionId": "s"])
            Event.record(.cardDetached, in: ctx, card: card, at: at, payload: ["sessionId": "s"])
            Event.record(.check, in: ctx, project: project, at: at, payload: ["command": "swift test"])
            Event.record(.commit, in: ctx, project: project, at: at, payload: ["hash": "abc"])
            Event.record(.fileChanged, in: ctx, project: project, at: at, payload: ["path": "a.swift"])
            Event.record(.note, in: ctx, project: project, at: at, payload: ["kind": "user.prompt", "text": "요청"])
            let session = makeSession(ctx, project, id: "gone-\(i)")
            session.endedAt = t0
        }
        for i in 0..<3 {
            Event.record(.fileChanged, in: ctx, card: card, at: t0 + Double(i), payload: ["path": "b.swift"])
            Event.record(.projectStatus, in: ctx, project: project, at: t0 + Double(i), payload: ["summary": .string("상황 \(i)")])
        }
        let doc = GuideDoc(relPath: "CLAUDE.md")
        ctx.insert(doc)
        for i in 0..<3 {
            let version = GuideVersion(content: "\(i)", at: t0 + Double(i), source: .local)
            ctx.insert(version)
            version.doc = doc
        }
        try ctx.save()

        // 하나씩 지운다: 이벤트 18건(종류 일곱 × 2 + 카드 파일 변경 2 + 지난 상황 2) → 세션 2 → 지침 판 2
        var steps: [RecordRetention.Result] = []
        for _ in 0..<23 {
            steps.append(RecordRetention.apply(in: ctx, now: now, limit: 1))
            try ctx.save()
        }
        #expect(steps.map(\.events) == Array(repeating: 1, count: 18) + Array(repeating: 0, count: 5))
        #expect(steps.map(\.sessions) == Array(repeating: 0, count: 18) + [1, 1, 0, 0, 0])
        #expect(steps.map(\.versions) == Array(repeating: 0, count: 20) + [1, 1, 0])
        #expect(steps.map(\.unfinished) == Array(repeating: true, count: 22) + [false])
        // 한 번에 돌린 것과 같은 결과
        #expect(count(Session.self, ctx) == 0 && count(GuideVersion.self, ctx) == 1)
        #expect(left(ctx, .fileChanged).count == 1 && left(ctx, .projectStatus).count == 1)
        #expect(count(Event.self, ctx) == 2)
    }

    // 같은 시각의 것 가운데 ID가 큰 쪽을 남긴다(넣은 순서와 무관).
    @Test func tiedLatestKeepsTheSameOneWhateverTheOrder() throws {
        for reversed in [false, true] {
            let (container, ctx) = try makeContext()
            _ = container
            let project = makeProject(ctx)
            let card = project.makeCard(in: ctx, title: "카드", status: .done, at: t0)
            let ids = ["00000000-0000-0000-0000-00000000000A", "00000000-0000-0000-0000-00000000000C",
                       "00000000-0000-0000-0000-00000000000B"].compactMap(UUID.init(uuidString:))
            for id in reversed ? ids.reversed() : ids {
                Event.record(.fileChanged, in: ctx, card: card, at: t0, payload: ["path": "a.swift"]).id = id
                Event.record(.projectStatus, in: ctx, project: project, at: t0, payload: ["summary": "상황"]).id = id
            }
            try ctx.save()
            #expect(RecordRetention.apply(in: ctx, now: now).events == 4)
            try ctx.save()
            #expect(left(ctx, .fileChanged).map(\.id) == [ids[1]] && left(ctx, .projectStatus).map(\.id) == [ids[1]])
            #expect(RecordRetention.apply(in: ctx, now: now) == .init())
        }
    }

    // 남기는 것이 상한보다 훨씬 많아도 지울 것을 끝까지 지운다.
    @Test func convergesWhenKeptFarOutnumberTheLimit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        // 카드 30장, 카드마다 마지막 초에 변경 넷(남는 것 30) + 그보다 뒤 시각의 카드 하나에 지울 것 다섯
        for i in 0..<30 {
            let card = project.makeCard(in: ctx, title: "카드 \(i)", status: .done, at: t0)
            for _ in 0..<4 { Event.record(.fileChanged, in: ctx, card: card, at: t0 + Double(i), payload: ["path": "a.swift"]) }
        }
        let late = project.makeCard(in: ctx, title: "늦은 카드", status: .done, at: t0)
        for i in 0..<6 { Event.record(.fileChanged, in: ctx, card: late, at: t0 + 100 + Double(i), payload: ["path": "b.swift"]) }
        try ctx.save()

        var deleted = 0, runs = 0
        while true {
            let result = RecordRetention.apply(in: ctx, now: now, limit: 2)
            try ctx.save()
            deleted += result.events
            runs += 1
            if !result.unfinished { break }
            #expect(result.events == 2)
            if runs > 100 { break }
        }
        #expect(deleted == 30 * 3 + 5 && runs == 48)
        #expect(left(ctx, .fileChanged).count == 31)
        #expect(Set(left(ctx, .fileChanged).compactMap { $0.card?.persistentModelID }).count == 31)
        #expect(RecordRetention.apply(in: ctx, now: now, limit: 2) == .init())
    }

    @Test func totalAddsEveryKind() {
        #expect(RecordRetention.Result(events: 2, sessions: 3, versions: 4, unfinished: false).total == 9)
    }

    // 카드마다 남기는 파일 변경이 앞에 쌓여 있어도 그 뒤의 지울 것을 찾는다.
    @Test func keptFileChangesDoNotHideOlderOnes() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let project = makeProject(ctx)
        func change(_ card: Card, at: Date) {
            Event.record(.fileChanged, in: ctx, card: card, at: at, payload: ["path": "a.swift"])
        }
        change(project.makeCard(in: ctx, title: "가", status: .done, at: t0), at: t0 + 10)
        change(project.makeCard(in: ctx, title: "나", status: .done, at: t0), at: t0 + 11)
        let busy = project.makeCard(in: ctx, title: "다", status: .done, at: t0)
        for i in 20...23 { change(busy, at: t0 + Double(i)) }
        try ctx.save()

        #expect(RecordRetention.apply(in: ctx, now: now, limit: 4) == .init(events: 3, sessions: 0, versions: 0, unfinished: false))
        try ctx.save()
        #expect(left(ctx, .fileChanged).map(\.at) == [t0 + 10, t0 + 11, t0 + 23])
    }
}
