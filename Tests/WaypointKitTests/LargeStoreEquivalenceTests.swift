import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-66: 큰 기록용으로 바꾼 질의(`UnfiledWork.count`·`items`, `DashboardQuery.rows`·`summary`·`lastActivityAt`)가
/// 바꾸기 전 구현(`Reference`, 그대로 옮겨 둠)과 같은 결과를 내는지 본다. 경계: 14일, 60분(멈춤), 끝난 세션, 보관 프로젝트,
/// 서브에이전트, 저장하지 않은 변경.

private let day: TimeInterval = 24 * 3600

/// TRK-66 전 구현. 결과 비교용으로만 둔다(앱 코드에서 부르지 않는다).
enum Reference {
    static func unfiledItems(for project: Project, now: Date, excluding current: Session? = nil) -> [String] {
        guard let context = project.modelContext else { return [] }
        let cutoff = now.addingTimeInterval(-UnfiledWork.window)
        let main = SessionKind.main.rawValue
        let projectID = project.id
        var ended = Set((try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.kindRaw == main && $0.lastSeenAt >= cutoff && $0.endedAt != nil && $0.project?.id == projectID
        }))) ?? [])
        if let current { ended.remove(current.persistentModelID) }
        guard !ended.isEmpty else { return [] }
        let raw = EventType.fileChanged.rawValue
        let events = (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate<Event> {
            $0.typeRaw == raw && $0.at >= cutoff && $0.card == nil && $0.project?.id == projectID
        }))) ?? []
        var owner: [PersistentIdentifier: PersistentIdentifier?] = [:]
        func mainID(of id: PersistentIdentifier, _ session: Session?) -> PersistentIdentifier? {
            if ended.contains(id) { return id }
            if let known = owner[id] { return known }
            let parent = session?.kind == .subagent ? session?.parent?.persistentModelID : nil
            let result = parent.flatMap { ended.contains($0) ? $0 : nil }
            owner[id] = result
            return result
        }
        var grouped: [PersistentIdentifier: [Event]] = [:]
        for event in events {
            guard let session = event.session, let id = mainID(of: session.persistentModelID, session) else { continue }
            grouped[id, default: []].append(event)
        }
        guard !grouped.isEmpty else { return [] }
        let filed = UnfiledWork.filedSessionIDs(for: project)
        let found = grouped.compactMap { id, events -> (Session, [Event])? in
            guard let session = context.model(for: id) as? Session, session.endedAt != nil,
                  !filed.contains(session.id), !UnfiledWork.everAttached(session)
            else { return nil }
            return (session, events)
        }.sorted {
            // 전 구현은 같은 시각끼리 순서가 정해지지 않았다(사전 순서). 새 구현처럼 ID순으로 맞춰 비교한다.
            $0.0.lastSeenAt != $1.0.lastSeenAt ? $0.0.lastSeenAt > $1.0.lastSeenAt : $0.0.id < $1.0.id
        }
        return found.map { "\($0.0.id)|\(UnfiledWork.paths($0.1).joined(separator: ","))" }
    }

    static func unfiledCount(for project: Project, now: Date) -> Int {
        guard let context = project.modelContext else { return 0 }
        let cutoff = now.addingTimeInterval(-UnfiledWork.window)
        let main = SessionKind.main.rawValue
        let projectID = project.id
        let ids = (try? context.fetchIdentifiers(FetchDescriptor<Session>(predicate: #Predicate<Session> {
            $0.kindRaw == main && $0.lastSeenAt >= cutoff && $0.endedAt != nil && $0.project?.id == projectID
        }))) ?? []
        guard !ids.isEmpty else { return 0 }
        let filed = UnfiledWork.filedSessionIDs(for: project)
        let raw = EventType.fileChanged.rawValue
        let projectPID = project.persistentModelID
        func hasChange(_ session: Session) -> Bool {
            let owners = [session] + (session.children ?? []).filter { $0.kind == .subagent }
            return owners.contains { owner in
                let sid = owner.persistentModelID
                var descriptor = FetchDescriptor<Event>(predicate: #Predicate<Event> {
                    $0.typeRaw == raw && $0.card == nil && $0.session?.persistentModelID == sid
                        && $0.project?.persistentModelID == projectPID && $0.at >= cutoff
                })
                descriptor.fetchLimit = 1
                return ((try? context.fetchCount(descriptor)) ?? 0) > 0
            }
        }
        return ids.reduce(0) { total, id in
            guard let session = context.model(for: id) as? Session, session.endedAt != nil,
                  !filed.contains(session.id), !UnfiledWork.everAttached(session), hasChange(session) else { return total }
            return total + 1
        }
    }

    /// `DashboardQuery.rows` 전 구현: 프로젝트의 세션 관계 전체를 돈다.
    static func rows(for project: Project, now: Date) -> [String] {
        let stallTimeout = SessionRules.defaultStallTimeout
        struct Pending {
            let card: Card?
            let session: Session
            let state: CardWorkState
            let attachedAt: Date
        }
        var pending: [Pending] = []
        for session in project.sessions ?? [] where session.endedAt == nil {
            let work: CardWorkState
            switch SessionRules.state(of: session, now: now, stallTimeout: stallTimeout) {
            case .live: work = .live
            case .stalled: work = .stalled
            case .ended: continue
            }
            let links = session.openCardSessions.filter { $0.card != nil }
            for link in links {
                pending.append(Pending(card: link.card, session: session, state: work, attachedAt: link.attachedAt))
            }
            if links.isEmpty, session.kind == .main,
               SessionRules.hasUnassignedWork(session, now: now, stallTimeout: stallTimeout) {
                pending.append(Pending(card: nil, session: session, state: work, attachedAt: session.startedAt))
            }
        }
        let sessionsWithRows = Set(pending.map { ObjectIdentifier($0.session) })
        func isNested(_ p: Pending) -> Bool {
            guard let parent = p.session.parent else { return false }
            return sessionsWithRows.contains(ObjectIdentifier(parent))
        }
        func byTime(_ a: Pending, _ b: Pending) -> Bool {
            if a.session.startedAt != b.session.startedAt { return a.session.startedAt < b.session.startedAt }
            if a.attachedAt != b.attachedAt { return a.attachedAt < b.attachedAt }
            let an = a.card?.number ?? 0, bn = b.card?.number ?? 0
            if an != bn { return an < bn }
            return a.session.id < b.session.id
        }
        let top = pending.filter { !isNested($0) }.sorted(by: byTime)
        let nested = pending.filter(isNested).sorted(by: byTime)
        var result: [String] = []
        func line(_ p: Pending, _ depth: Int) -> String {
            "\(p.session.id)|\(p.card?.displayID ?? "-")|\(p.state.rawValue)|\(depth)|\(p.card == nil ? "-" : "\(p.attachedAt)")"
        }
        var index = 0
        while index < top.count {
            let session = top[index].session
            while index < top.count, top[index].session === session {
                result.append(line(top[index], 0))
                index += 1
            }
            for p in nested where p.session.parent === session { result.append(line(p, 1)) }
        }
        return result
    }

    static func summary(for project: Project, now: Date) -> String {
        var live = 0, stalled = 0, next = 0, idea = 0
        for card in project.cards ?? [] {
            switch CardRules.workState(of: card, now: now) {
            case .live: live += 1
            case .stalled: stalled += 1
            case .none: break
            }
            switch card.status {
            case .next: next += 1
            case .idea: idea += 1
            default: break
            }
        }
        for session in project.sessions ?? [] where session.kind == .main && session.endedAt == nil {
            guard !session.openCardSessions.contains(where: { $0.card != nil }),
                  SessionRules.hasUnassignedWork(session, now: now) else { continue }
            switch SessionRules.state(of: session, now: now) {
            case .live: live += 1
            case .stalled: stalled += 1
            case .ended: break
            }
        }
        return "\(live)|\(stalled)|\(next)|\(idea)|\(lastActivityAt(of: project).map { "\($0)" } ?? "nil")"
    }

    static func lastActivityAt(of project: Project) -> Date? {
        let times: [Date] = [project.lastEventAt].compactMap { $0 }
            + (project.sessions ?? []).map(\.lastSeenAt)
            + (project.cards ?? []).map(\.updatedAt)
        return times.max()
    }
}

/// 새 구현을 비교용 문자열로.
enum Current {
    static func unfiledItems(for project: Project, now: Date, excluding current: Session? = nil) -> [String] {
        UnfiledWork.items(for: project, now: now, excluding: current)
            .map { "\($0.session.id)|\($0.files.joined(separator: ","))" }
    }

    static func rows(for project: Project, now: Date) -> [String] {
        DashboardQuery.rows(for: project, now: now).map { row in
            "\(row.session.id)|\(row.card?.displayID ?? "-")|\(row.workState.rawValue)|\(row.depth)|"
                + (row.attachedAt.map { "\($0)" } ?? "-")
        }
    }

    static func summary(for project: Project, now: Date) -> String {
        let s = DashboardQuery.summary(for: project, now: now)
        return "\(s.liveCount)|\(s.stalledCount)|\(s.nextCount)|\(s.ideaCount)|\(s.lastActivityAt.map { "\($0)" } ?? "nil")"
    }
}

/// 같은 결과인지 한 번에 본다. 다르면 무엇이 다른지 남긴다.
func expectSameAsReference(_ projects: [Project], at times: [Date], excluding current: Session? = nil,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    for project in projects {
        for now in times {
            let label = "\(project.key) now=\(now.timeIntervalSince(t0))"
            #expect(Current.unfiledItems(for: project, now: now, excluding: current)
                    == Reference.unfiledItems(for: project, now: now, excluding: current), "\(label)",
                    sourceLocation: sourceLocation)
            #expect(UnfiledWork.count(for: project, now: now) == Reference.unfiledCount(for: project, now: now), "\(label)",
                    sourceLocation: sourceLocation)
            #expect(Current.rows(for: project, now: now) == Reference.rows(for: project, now: now), "\(label)",
                    sourceLocation: sourceLocation)
            #expect(Current.summary(for: project, now: now) == Reference.summary(for: project, now: now), "\(label)",
                    sourceLocation: sourceLocation)
            #expect(DashboardQuery.lastActivityAt(of: project) == Reference.lastActivityAt(of: project), "\(label)",
                    sourceLocation: sourceLocation)
        }
    }
}

/// 경계가 모인 픽스처. `now` 기준으로 만든다.
private struct Fixture {
    let projects: [Project]
    let now: Date
    /// 경계 시각들(14일·60분 바로 앞뒤)
    let times: [Date]
}

@discardableResult
private func ended(_ ctx: ModelContext, _ project: Project, _ id: String, at date: Date,
                   files: [(String, Date)] = [], provider: AgentProvider = .claude) -> Session {
    let s = Session(id: id, startedAt: date - 3600, lastSeenAt: date, provider: provider)
    ctx.insert(s)
    s.project = project
    s.endedAt = date
    for (path, at) in files {
        Event.record(.fileChanged, in: ctx, project: project, session: s, at: at, payload: ["path": .string(path)])
    }
    return s
}

private func change(_ ctx: ModelContext, _ project: Project, _ session: Session, _ path: String, at: Date, card: Card? = nil) {
    Event.record(.fileChanged, in: ctx, project: project, card: card, session: session, at: at,
                 payload: ["path": .string(path)])
}

private func buildFixture(_ ctx: ModelContext) -> Fixture {
    let now = t0 + 40 * day
    let cutoff = now - 14 * day
    let p = makeProject(ctx)
    let other = makeProject(ctx, key: "OTH", name: "다른")
    let archived = makeProject(ctx, key: "ARC", name: "보관")
    let card = p.makeCard(in: ctx, title: "카드", status: .next, at: t0)
    let done = p.makeCard(in: ctx, title: "끝낸 카드", status: .done, at: t0)
    _ = p.makeCard(in: ctx, title: "아이디어", status: .idea, at: t0)

    // 14일 경계: 마지막 활동·파일 변경이 기준 시각 바로 앞·위·뒤
    ended(ctx, p, "edge-before", at: cutoff - 1, files: [("a.swift", cutoff - 1)])
    ended(ctx, p, "edge-exact", at: cutoff, files: [("a.swift", cutoff)])
    ended(ctx, p, "edge-after", at: cutoff + 1, files: [("b.swift", cutoff - 10), ("c.swift", cutoff + 1)])
    ended(ctx, p, "many-files", at: now - 2 * day,
          files: [("a.swift", now - 3 * day), ("b.swift", now - 2 * day - 50), ("a.swift", now - 2 * day - 40),
                  ("d.swift", now - 2 * day - 30), ("c.swift", now - 2 * day - 30)])
    ended(ctx, p, "codex-1", at: now - 3 * day, files: [("x.swift", now - 3 * day - 5)], provider: .codex)
    ended(ctx, p, "no-files", at: now - day)
    // 카드 있는 파일 변경만
    let withCard = ended(ctx, p, "card-change", at: now - day)
    change(ctx, p, withCard, "k.swift", at: now - day - 10, card: card)
    // 붙었다 풀린 세션, 서브에이전트만 붙었던 세션
    let attached = ended(ctx, p, "attached", at: now - day, files: [("e.swift", now - day - 20)])
    CardLifecycle.attach(card, attached, at: now - day - 500, in: ctx)
    CardLifecycle.detach(card, attached, at: now - day - 400, in: ctx)
    let parentAttached = ended(ctx, p, "sub-attached-parent", at: now - day, files: [("f.swift", now - day - 20)])
    let sub = makeSession(ctx, p, id: "sub-attached", startedAt: now - day - 500, parent: parentAttached)
    sub.endedAt = now - day
    CardLifecycle.attach(card, sub, at: now - day - 450, in: ctx)
    CardLifecycle.detach(card, sub, at: now - day - 440, in: ctx)
    // 파일 변경이 서브에이전트에만 있는 세션
    let parentOnly = ended(ctx, p, "sub-files-parent", at: now - 4 * day)
    let worker = makeSession(ctx, p, id: "sub-files", startedAt: now - 4 * day - 600, lastSeenAt: now - 4 * day - 100,
                             parent: parentOnly)
    worker.endedAt = now - 4 * day - 100
    change(ctx, p, worker, "g.swift", at: now - 4 * day - 200)
    change(ctx, p, worker, "g.swift", at: now - 4 * day - 150)
    // 넘긴 세션
    ended(ctx, p, "filed", at: now - day, files: [("h.swift", now - day - 5)])
    Event.record(.sessionFiled, in: ctx, project: p, at: now - 100, payload: ["sessionId": "filed", "outcome": "dismissed"])
    // 다른 프로젝트에 남긴 변경
    let crossed = ended(ctx, p, "crossed", at: now - day)
    change(ctx, other, crossed, "o.swift", at: now - day - 5)
    // 다른 프로젝트·보관 프로젝트의 끝난 세션
    ended(ctx, other, "other-1", at: now - day, files: [("o.swift", now - day - 5)])
    ended(ctx, archived, "archived-1", at: now - day, files: [("z.swift", now - day - 5)])

    // 끝나지 않은 세션: 60분 경계(멈춤), 카드 붙음, 서브에이전트, 끝낸 카드에서 떨어진 대화
    let stall = SessionRules.defaultStallTimeout
    let live = makeSession(ctx, p, id: "live", startedAt: now - 2 * 3600, lastSeenAt: now - stall)
    change(ctx, p, live, "l.swift", at: now - stall - 10)
    let stalled = makeSession(ctx, p, id: "stalled", startedAt: now - 3 * 3600, lastSeenAt: now - stall - 1)
    CardLifecycle.attach(card, stalled, at: now - 3 * 3600 + 60, in: ctx)
    let liveSub = makeSession(ctx, p, id: "live-sub", startedAt: now - 1800, lastSeenAt: now - 60, parent: live)
    liveSub.activityRaw = SessionActivity.working.rawValue
    CardLifecycle.attach(card, liveSub, at: now - 1700, in: ctx)
    change(ctx, p, liveSub, "carded.swift", at: now - 1600, card: card)
    change(ctx, p, liveSub, "loose.swift", at: now - 1500)
    change(ctx, p, stalled, "s1.swift", at: now - 3 * 3600 + 120, card: card)
    change(ctx, p, stalled, "s2.swift", at: now - 3 * 3600 + 180, card: card)
    change(ctx, p, stalled, "s0.swift", at: now - 3 * 3600 + 200)
    let finished = makeSession(ctx, p, id: "after-done", startedAt: now - 5000, lastSeenAt: now - 100)
    CardLifecycle.attach(done, finished, at: now - 4900, in: ctx)
    CardLifecycle.detach(done, finished, at: now - 4000, in: ctx)
    finished.lastPromptAt = now - 4500
    let prompted = makeSession(ctx, p, id: "after-done-prompted", startedAt: now - 5000, lastSeenAt: now - 50)
    CardLifecycle.attach(done, prompted, at: now - 4900, in: ctx)
    CardLifecycle.detach(done, prompted, at: now - 4000, in: ctx)
    prompted.lastPromptAt = now - 3000
    _ = makeSession(ctx, other, id: "other-live", startedAt: now - 600, lastSeenAt: now - 60)
    _ = makeSession(ctx, archived, id: "archived-live", startedAt: now - 600, lastSeenAt: now - 60)

    var times: [Date] = [now, now - 30 * day, now + 2 * day]
    for offset in [-1.0, 0, 1] {
        for base in [cutoff, cutoff - 10, cutoff - 1, cutoff + 1, now - 4 * day - 200] {
            times.append(base + 14 * day + offset)
        }
        times.append(now + offset)
        times.append(now - 60 + stall + offset)
    }
    return Fixture(projects: [p, other, archived], now: now, times: times)
}

@Suite struct LargeStoreEquivalenceTests {
    @Test func boundariesMatchReferenceBeforeSave() throws {
        let (c, ctx) = try makeContext(); _ = c
        let f = buildFixture(ctx)
        // 픽스처가 경계를 실제로 밟는지(빈 결과끼리 같아서 통과하지 않게)
        let p = f.projects[0]
        #expect(Set(Current.unfiledItems(for: p, now: f.now).map { String($0.split(separator: "|")[0]) })
                == ["edge-exact", "edge-after", "many-files", "codex-1", "sub-files-parent"])
        #expect(Current.rows(for: p, now: f.now).count >= 4)
        expectSameAsReference(f.projects, at: f.times)
    }

    @Test func boundariesMatchReferenceAfterSave() throws {
        let container = try makeDiskContainer("trk66")
        let ctx = ModelContext(container)
        let f = buildFixture(ctx)
        try ctx.save()
        expectSameAsReference(f.projects, at: f.times)
        // 새 context(관계를 처음 읽는다)에서도
        let fresh = ModelContext(container)
        let projects = try fresh.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.key)]))
        expectSameAsReference(projects, at: f.times)
    }

    /// 저장하지 않은 변경: `SessionStart`는 새 세션을 넣은 뒤 저장 전에 블록을 만든다. 끝남·되살림·활동 시각 변경도 저장 전에 읽힌다.
    @Test func pendingChangesMatchReference() throws {
        let container = try makeDiskContainer("trk66-pending")
        let ctx = ModelContext(container)
        let f = buildFixture(ctx)
        try ctx.save()
        let p = f.projects[0]
        let sessions = try ctx.fetch(FetchDescriptor<Session>())
        func session(_ id: String) throws -> Session { try #require(sessions.first { $0.id == id }) }

        // 새 세션(저장 전), 끝난 세션 되살림, 열린 세션 끝냄, 마지막 활동을 가장 늦게
        let fresh = makeSession(ctx, p, id: "fresh", startedAt: f.now - 10, lastSeenAt: f.now + 3600)
        try session("codex-1").endedAt = nil
        try session("live").endedAt = f.now - 5
        try session("many-files").lastSeenAt = f.now + 7200
        _ = ended(ctx, p, "late-ended", at: f.now - 30, files: [("n.swift", f.now - 40)])
        // 저장된 세션에 저장 전 변경(본인·서브에이전트), 저장 전 넘김·연결
        change(ctx, p, try session("no-files"), "m.swift", at: f.now - day - 20)
        change(ctx, p, try session("sub-attached"), "q.swift", at: f.now - day - 30)
        let worker = makeSession(ctx, p, id: "late-worker", startedAt: f.now - 2 * day, parent: try session("card-change"))
        change(ctx, p, worker, "w.swift", at: f.now - day - 15)
        Event.record(.sessionFiled, in: ctx, project: p, at: f.now - 10, payload: ["sessionId": "edge-after", "outcome": "dismissed"])
        let card = try #require(p.cards?.first { $0.title == "카드" })
        CardLifecycle.attach(card, try session("codex-1"), at: f.now - 20, in: ctx)
        CardLifecycle.attach(card, makeSession(ctx, p, id: "late-sub", startedAt: f.now - 20, parent: try session("edge-exact")),
                             at: f.now - 20, in: ctx)
        // 저장 전 다른 프로젝트로 옮김(session_bind)
        try session("other-live").project = p
        try session("after-done").project = f.projects[1]
        try session("after-done").lastSeenAt = f.now + 9000
        expectSameAsReference(f.projects, at: f.times, excluding: fresh)
        #expect(DashboardQuery.lastActivityAt(of: p) == f.now + 7200)
        #expect(DashboardQuery.lastActivityAt(of: f.projects[1]) == f.now + 9000)
        #expect(Current.rows(for: p, now: f.now).contains { $0.hasPrefix("other-live|") })
        let ids = Set(Current.unfiledItems(for: p, now: f.now).map { String($0.split(separator: "|")[0]) })
        #expect(ids == ["late-ended", "no-files", "card-change", "many-files", "sub-files-parent"])
    }
}

/// 저장소 **사본**에서 새 구현과 전 구현을 비교하고 시간을 잰다. `WAYPOINT_REAL_STORE_COPY`(사본 `.store` 경로)가 있을 때만 돈다.
@Suite struct LargeStoreCopyTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"] != nil))
    func copyMatchesReferenceAndTiming() throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-trk66-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Waypoint.store")
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: URL(fileURLWithPath: url.path + suffix))
            }
        }
        let container = try WaypointStore.makeContainer(url: url)
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Project>())
        let projects = all.filter { $0.archivedAt == nil }
        let latest = all.compactMap(\.lastEventAt).max() ?? Date()
        let times = [latest, latest + 3600, latest - 7 * day, Date()]
        expectSameAsReference(all, at: times)

        func median(_ runs: Int, _ body: () -> Void) -> Double {
            let times = (0..<runs).map { _ -> Double in
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }.sorted()
            return times[times.count / 2]
        }
        // 매번 새 context: 앱이 저장 뒤 다시 읽는 경우에 가깝게(관계·행 캐시 없이)
        func cold(_ body: ([Project]) -> Void) -> Double {
            median(9) {
                let fresh = ModelContext(container)
                let ps = ((try? fresh.fetch(FetchDescriptor<Project>())) ?? []).filter { $0.archivedAt == nil }
                body(ps)
            }
        }
        let now = Date()
        let report = [
            ("unfiledCount", cold { ps in for p in ps { _ = UnfiledWork.count(for: p, now: now) } }),
            ("unfiledItems", cold { ps in for p in ps { _ = UnfiledWork.items(for: p, now: now, limit: 3) } }),
            ("rows", cold { ps in for p in ps { _ = DashboardQuery.rows(for: p, now: now) } }),
            ("summary", cold { ps in for p in ps { _ = DashboardQuery.summary(for: p, now: now) } }),
            ("board", cold { ps in _ = ProjectSituation.board(for: ps, now: now) }),
            ("overview", cold { ps in _ = DashboardOverview(projects: ps, now: now) }),
            ("block", cold { ps in
                for p in ps {
                    let fresh = Session(id: "timing-\(UUID().uuidString)", startedAt: now, lastSeenAt: now)
                    p.modelContext?.insert(fresh)
                    fresh.project = p
                    _ = SessionContext.text(project: p, session: fresh, now: now)
                }
            }),
            ("refCount", cold { ps in for p in ps { _ = Reference.unfiledCount(for: p, now: now) } }),
            ("refRows", cold { ps in for p in ps { _ = Reference.rows(for: p, now: now) } }),
            ("refSummary", cold { ps in for p in ps { _ = Reference.summary(for: p, now: now) } }),
        ]
        // 앱처럼 오래 사는 context 하나에서 대시보드 한 번 그리기(통합 집계 + 진행 작업 + 상황판 + 타일의 최근 파일 + 사이드바)
        let warm = ModelContext(container)
        let warmProjects = try warm.fetch(FetchDescriptor<Project>()).filter { $0.archivedAt == nil }
        func refresh() {
            let overview = DashboardOverview(projects: warmProjects, now: now)
            let rows = overview.groups.flatMap(\.rows)
            _ = WorkOverlap.byRow(rows.filter { $0.workState == .live }, now: now)
            _ = ProjectSituation.board(for: warmProjects, now: now)
            for row in rows {
                _ = row.card.map { SessionFormat.recentFileName(card: $0, session: row.session) }
                    ?? SessionFormat.recentFileName(session: row.session)
            }
            for p in warmProjects { _ = DashboardQuery.summary(for: p, now: now) }
        }
        refresh()
        // 벽시계와 이 스레드의 CPU 시간(기계 부하에 덜 흔들린다)
        var wall: [Double] = [], cpu: [Double] = []
        for _ in 0..<15 {
            let start = DispatchTime.now().uptimeNanoseconds, startCPU = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            refresh()
            wall.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            cpu.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - startCPU) / 1_000_000)
        }
        wall.sort(); cpu.sort()
        print(String(format: "[trk66-refresh] warm dashboard refresh wall median=%.1fms max=%.1fms cpu median=%.1fms max=%.1fms",
                     wall[wall.count / 2], wall.last ?? 0, cpu[cpu.count / 2], cpu.last ?? 0))
        print("[trk66-timing] projects=\(projects.count) sessions=\(try ctx.fetchCount(FetchDescriptor<Session>())) "
              + "events=\(try ctx.fetchCount(FetchDescriptor<Event>())) "
              + report.map { String(format: "%@=%.1fms", $0.0, $0.1) }.joined(separator: " "))
    }
}
