import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-62·63: 정리 안 된 작업, 프로젝트 지금 상황, 자동 갱신 지표.

private let day: TimeInterval = 24 * 3600

/// 끝난 메인 세션 하나. `files` 경로마다 카드 없는 `file.changed`를 남긴다.
@discardableResult
private func endedSession(
    _ ctx: ModelContext, _ project: Project, id: String, at date: Date, files: [String] = ["a.swift"],
    provider: AgentProvider = .claude
) -> Session {
    let s = Session(id: id, startedAt: date - 600, lastSeenAt: date, provider: provider)
    ctx.insert(s)
    s.project = project
    s.endedAt = date
    for (i, path) in files.enumerated() {
        Event.record(.fileChanged, in: ctx, project: project, session: s, at: date - 300 + Double(i),
                     payload: ["path": .string(path), "added": 1, "removed": 0])
    }
    return s
}

private func tools(_ ctx: ModelContext, at date: Date) -> MCPTools {
    MCPTools(context: ctx, home: "/Users/me", now: { date })
}

/// 픽스처의 `session_id`를 바꿔 보낸다.
@discardableResult
private func send(_ h: HookHarness, _ name: String, session: String, at date: Date) throws -> String? {
    var object = try #require(try JSONSerialization.jsonObject(with: try fixture(name)) as? [String: Any])
    object["session_id"] = session
    return h.processor.handle(event: nil, json: try JSONSerialization.data(withJSONObject: object), at: date)
}

@Suite struct UnfiledWorkBlockTests {
    @Test func listsUpToThreeNewestFirst() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 20 * day
        endedSession(ctx, p, id: "aaaaaaaa-1", at: now - 4 * day, files: ["x.swift"])
        endedSession(ctx, p, id: "bbbbbbbb-2", at: now - 3 * day, files: ["a.swift", "b.swift", "a.swift", "c.swift", "d.swift"])
        endedSession(ctx, p, id: "cccccccc-3", at: now - 2 * day, files: ["y.swift"], provider: .codex)
        endedSession(ctx, p, id: "dddddddd-4", at: now - 1 * day, files: ["z.swift"])
        let current = makeSession(ctx, p, id: "current", startedAt: now, lastSeenAt: now)

        let lines = SessionContext.text(project: p, session: current, now: now).components(separatedBy: "\n")
        let ts = { (d: Date) in TimeFormat.timestamp(d, now: now) }
        #expect(lines == [
            "Waypoint: LDG (가계부 앱)",
            "sessionId: current",
            "정리 안 된 작업:",
            "- \(ts(now - day)) · Claude Code · 파일 1개: z.swift · dddddddd",
            "- \(ts(now - 2 * day)) · Codex · 파일 1개: y.swift · codex:cccccccc",
            "- \(ts(now - 3 * day)) · Claude Code · 파일 4개: a.swift, d.swift, c.swift 외 1 · bbbbbbbb",
            "- 외 1개",
            SessionContext.skillHint,
        ])
    }

    /// 경계: 14일 밖, 파일 0개, 카드 연결 있음(풀렸어도·서브에이전트), 이미 처리함, 끝나지 않음, 다른 프로젝트 파일.
    @Test func excludesOutsideConditions() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let other = makeProject(ctx, key: "OTH", name: "other")
        let now = t0 + 30 * day
        endedSession(ctx, p, id: "old-14d", at: now - 14 * day - 60)
        endedSession(ctx, p, id: "edge-14d", at: now - 14 * day + 360) // 파일 변경은 끝나기 300초 전 = 기간 안 60초
        endedSession(ctx, p, id: "early-files", at: now - 14 * day + 240) // 끝은 기간 안, 파일 변경은 기간 밖
        endedSession(ctx, p, id: "nofiles", at: now - day, files: [])
        let attached = endedSession(ctx, p, id: "attached", at: now - day)
        let card = p.makeCard(in: ctx, title: "카드", status: .next, at: t0)
        CardLifecycle.attach(card, attached, at: now - day - 500, in: ctx)
        CardLifecycle.detach(card, attached, at: now - day - 400, in: ctx)
        let parent = endedSession(ctx, p, id: "subattached", at: now - day)
        let sub = makeSession(ctx, p, id: "sub-agent", startedAt: now - day - 500, parent: parent)
        CardLifecycle.attach(card, sub, at: now - day - 450, in: ctx)
        CardLifecycle.detach(card, sub, at: now - day - 440, in: ctx)
        endedSession(ctx, p, id: "filed", at: now - day)
        Event.record(.sessionFiled, in: ctx, project: p, at: now - 100,
                     payload: ["sessionId": "filed", "outcome": "dismissed"])
        let live = endedSession(ctx, p, id: "live", at: now - day)
        live.endedAt = nil
        let crossed = Session(id: "crossed", startedAt: now - day, lastSeenAt: now - day)
        ctx.insert(crossed); crossed.project = p; crossed.endedAt = now - day
        Event.record(.fileChanged, in: ctx, project: other, session: crossed, at: now - day, payload: ["path": "o.swift"])

        let ids = UnfiledWork.items(for: p, now: now).map(\.session.id)
        #expect(ids == ["edge-14d"])
        #expect(card.status == .next)
    }

    /// 끝난 세션이 재개로 다시 열리면 그 세션의 블록에 자기 자신을 넣지 않는다.
    @Test func resumedSessionDoesNotListItself() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PostToolUse-Edit", at: t0 + 10)
        try h.send("doc-SessionEnd", at: t0 + 20)
        try h.context.save()
        let resumed = try #require(try h.send("doc-SessionStart", at: t0 + 600))
        #expect(!resumed.contains("정리 안 된 작업"))
        #expect(try h.session()?.endedAt == nil)
    }

    @Test func noSectionWithoutUnfiledWork() throws {
        let h = try HookHarness()
        let text = try #require(try h.send("doc-SessionStart", at: t0))
        #expect(!text.contains("정리 안 된 작업"))
        #expect(!text.contains("지금 상황"))
    }

    /// 훅 픽스처 흐름: 카드 없이 파일을 바꾸고 끝난 세션 → 다음 SessionStart 블록에 보임 → work_file로 이으면 사라짐.
    @Test func hookFlowShowsThenFiles() throws {
        let h = try HookHarness()
        try h.send("doc-SessionStart", at: t0)
        try h.send("doc-PostToolUse-Edit", at: t0 + 10)
        try h.send("doc-SessionEnd", at: t0 + 20)
        let card = h.project.makeCard(in: h.context, title: "영수증 파서", status: .next, at: t0)

        let next = "11111111-2222-4333-8444-555555555555"
        let text = try #require(try send(h, "doc-SessionStart", session: next, at: t0 + 3600))
        let ended = try #require(try h.session())
        #expect(ended.endedAt != nil)
        #expect(text.contains("정리 안 된 작업:\n- \(TimeFormat.timestamp(ended.lastSeenAt, now: t0 + 3600)) · Claude Code · 파일 1개: Ledger/OCR/ReceiptParser.swift · 7f2a9c41\n"))

        let result = try tools(h.context, at: t0 + 3700).call("work_file", ["sessionId": "7f2a9c41", "cardId": "LDG-1"])
        #expect(result["outcome"] == "filed")
        #expect(result["files"]?.numberValue == 1)
        #expect(CardHistoryFormat.changedFiles(for: card).map(\.path) == ["Ledger/OCR/ReceiptParser.swift"])
        #expect(card.status == .next)
        #expect((card.cardSessions ?? []).isEmpty)

        let again = try #require(try send(h, "doc-SessionStart", session: "99999999-2222-4333-8444-555555555555", at: t0 + 3800))
        #expect(!again.contains("정리 안 된 작업"))
    }

    // 파일 목록은 앞의 limit개 세션 것만 읽는다.
    @Test func filesAreReadOnlyForFirstLimitSessions() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 20 * day
        endedSession(ctx, p, id: "newer", at: now - day, files: ["n.swift"])
        endedSession(ctx, p, id: "older", at: now - 2 * day, files: ["o.swift"])
        let items = UnfiledWork.items(for: p, now: now, limit: 1)
        #expect(items.map(\.session.id) == ["newer", "older"])
        #expect(items.map(\.files) == [["n.swift"], []])
    }

    // 서브에이전트만 파일을 바꿨어도 부모 세션이 나온다. 딱 14일 전 변경까지 센다.
    @Test func subagentChangeAtWindowEdgeListsParent() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 30 * day
        let parent = endedSession(ctx, p, id: "parent", at: now - day, files: [])
        let sub = makeSession(ctx, p, id: "sub", startedAt: now - 14 * day, parent: parent)
        Event.record(.fileChanged, in: ctx, project: p, session: sub, at: now - 14 * day, payload: ["path": "s.swift"])
        let items = UnfiledWork.items(for: p, now: now)
        #expect(items.map(\.session.id) == ["parent"])
        #expect(items.first?.files == ["s.swift"])
        #expect(UnfiledWork.count(for: p, now: now) == 1)
    }

    // 서브에이전트가 파일을 안 바꿨거나 카드에 남긴 변경뿐이면 부모는 나오지 않는다.
    @Test func subagentWithoutUnfiledChangeDoesNotListParent() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 30 * day
        let quiet = endedSession(ctx, p, id: "quiet-parent", at: now - day, files: [])
        _ = makeSession(ctx, p, id: "quiet-sub", startedAt: now - day, parent: quiet)
        let carded = endedSession(ctx, p, id: "carded-parent", at: now - day, files: [])
        let sub = makeSession(ctx, p, id: "carded-sub", startedAt: now - day, parent: carded)
        let card = p.makeCard(in: ctx, title: "카드", status: .next, at: t0)
        Event.record(.fileChanged, in: ctx, project: p, card: card, session: sub, at: now - day, payload: ["path": "c.swift"])
        #expect(UnfiledWork.items(for: p, now: now).isEmpty)
        #expect(UnfiledWork.count(for: p, now: now) == 0)
    }

    // 세션 없이 남은 파일 변경은 어느 세션의 파일 목록에도 넣지 않는다.
    @Test func sessionlessChangeIsNotListedUnderAnySession() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let now = t0 + 20 * day
        endedSession(ctx, p, id: "only", at: now - day, files: ["mine.swift"])
        Event.record(.fileChanged, in: ctx, project: p, at: now - day, payload: ["path": "orphan.swift"])
        #expect(UnfiledWork.items(for: p, now: now).map(\.files) == [["mine.swift"]])
    }

    // 파일이 딱 세 개면 「외 n」을 붙이지 않는다.
    @Test func lineWithExactlyThreeFilesHasNoRest() {
        let session = Session(id: "abcdef123456", startedAt: t0, lastSeenAt: t0)
        let item = UnfiledWork.Item(session: session, files: ["a.swift", "b.swift", "c.swift"])
        let now = t0 + 3600
        #expect(UnfiledWork.line(item, now: now)
                == "- \(TimeFormat.timestamp(t0, now: now)) · Claude Code · 파일 3개: a.swift, b.swift, c.swift · abcdef12")
    }

    // 저장소에 넣지 않은 프로젝트는 갖고 있는 기록에서 처리한 세션을 찾는다.
    @Test func filedSessionIDsWithoutStoreReadsOwnEvents() {
        let p = Project(key: "TMP", name: "tmp", createdAt: t0)
        let filed = Event(type: .sessionFiled, at: t0, payload: EventValue.encode(["sessionId": "done"]))
        let note = Event(type: .note, at: t0, payload: EventValue.encode(["sessionId": "noise"]))
        filed.project = p
        note.project = p
        p.events = [filed, note]
        #expect(UnfiledWork.filedSessionIDs(for: p) == ["done"])
    }
}

@Suite struct ProjectStatusTests {
    @Test func blockShowsLatestStatus() throws {
        let h = try HookHarness()
        let t = tools(h.context, at: t0)
        _ = try t.call("project_status", ["project": "LDG", "text": "예전 상황"])
        let later = tools(h.context, at: t0 + 600)
        _ = try later.call("project_status", ["project": "LDG", "text": "  OCR 파서 진행 중\n\n다음: 테스트 정리  ", "provider": "codex"])
        let now = t0 + 3 * 3600
        let text = try #require(try h.send("doc-SessionStart", at: now))
        #expect(text.hasPrefix("""
            Waypoint: LDG (가계부 앱)
            sessionId: \(HookHarness.sessionID)
            지금 상황 (\(TimeFormat.relative(t0 + 600, now: now)), Codex):
              OCR 파서 진행 중
              다음: 테스트 정리
            """))
        #expect(!text.contains("예전 상황"))
    }

    @Test func staleAfterSevenDays() throws {
        let h = try HookHarness()
        _ = try tools(h.context, at: t0).call("project_status", ["project": "LDG", "text": "상황"])
        let fresh = try #require(try send(h, "doc-SessionStart", session: "s-fresh", at: t0 + 7 * day - 60))
        #expect(fresh.contains("지금 상황 (\(TimeFormat.relative(t0, now: t0 + 7 * day - 60)), Claude Code):"))
        let stale = try #require(try send(h, "doc-SessionStart", session: "s-stale", at: t0 + 7 * day + 60))
        #expect(stale.contains("지금 상황 (\(TimeFormat.relative(t0, now: t0 + 7 * day + 60)), Claude Code, 오래됨):"))
    }

    @Test func lengthLimitsAndRead() throws {
        let h = try MCPHarness()
        #expect(try h.fails("project_status", ["project": "PRB", "text": "   \n "]) == "text가 비어 있음")
        let long = String(repeating: "가", count: ProjectStatus.characterLimit + 1)
        #expect(try h.fails("project_status", ["project": "PRB", "text": .string(long)]).contains("600자·8줄 이내"))
        let nine = (1...9).map { "줄 \($0)" }.joined(separator: "\n")
        #expect(try h.fails("project_status", ["project": "PRB", "text": .string(nine)]).hasSuffix("9줄)"))
        let exact = String(repeating: "가", count: ProjectStatus.characterLimit)
        _ = try h.ok("project_status", ["project": "PRB", "text": .string(exact)])
        #expect(try h.ok("project_status", ["project": "PRB"])["status"]?["text"]?.stringValue == exact)

        let written = try tools(h.context, at: t0 + 120).call(
            "project_status", ["project": "PRB", "text": "새 상황", "sessionId": .string(MCPHarness.sessionID)])
        #expect(written["status"]?["sessionId"]?.stringValue == MCPHarness.sessionID)
        #expect(written["status"]?["stale"] == false)
        let read = try h.ok("project_status", ["project": "PRB"])
        #expect(read["status"]?["text"] == "새 상황")
        #expect(read["status"]?["provider"] == "claude")
        let event = try #require(ProjectStatus.events(for: h.project).max { $0.at < $1.at })
        #expect(event.session === h.session)
        #expect(event.payloadValues["text"] == nil) // 옛 앱에 메모로 보이지 않게
    }

    @Test func readWithoutStatusIsNull() throws {
        let h = try MCPHarness()
        #expect(try h.ok("project_status", ["project": "PRB"])["status"] == .null)
        _ = try h.fails("project_status", ["project": "NOPE", "text": "x"])
    }
}

@Suite struct WorkFileTests {
    @Test func dismissKeepsEventsUnlinked() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let s = endedSession(ctx, p, id: "abcdef12-0000", at: t0)
        let result = try tools(ctx, at: t0 + 60).call("work_file", ["sessionId": "abcdef12-0000"])
        #expect(result["outcome"] == "dismissed")
        #expect((s.events ?? []).filter { $0.type == .fileChanged }.allSatisfy { $0.card == nil })
        #expect(UnfiledWork.items(for: p, now: t0 + 60).isEmpty)
        #expect(throws: MCPToolError.self) { try tools(ctx, at: t0 + 70).call("work_file", ["sessionId": "abcdef12-0000"]) }
        // 넘긴 세션도 나중에 카드에 이을 수 있고, 이은 뒤에는 다시 처리하지 않는다
        p.makeCard(in: ctx, title: "카드", at: t0)
        let filed = try tools(ctx, at: t0 + 80).call("work_file", ["sessionId": "abcdef12-0000", "cardId": "LDG-1"])
        #expect(filed["outcome"] == "filed")
        #expect(throws: MCPToolError.self) {
            try tools(ctx, at: t0 + 90).call("work_file", ["sessionId": "abcdef12-0000", "cardId": "LDG-1"])
        }
    }

    @Test func fileMovesFilesCommitsChecksOnly() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let s = endedSession(ctx, p, id: "abcdef12-0000", at: t0, files: ["a.swift", "a.swift", "b.swift"])
        let sub = makeSession(ctx, p, id: "sub", startedAt: t0 - 100, parent: s)
        Event.record(.fileChanged, in: ctx, project: p, session: sub, at: t0 - 50, payload: ["path": "c.swift"])
        Event.record(.commit, in: ctx, project: p, session: s, at: t0 - 40, payload: ["hash": "abc1234", "message": "m"])
        Event.record(.note, in: ctx, project: p, session: s, at: t0 - 30, payload: ["kind": "user.prompt", "text": "요청"])
        let card = p.makeCard(in: ctx, title: "카드", status: .idea, at: t0)
        let updatedAt = card.updatedAt

        let result = try tools(ctx, at: t0 + 60).call("work_file", ["sessionId": "abcdef12", "cardId": "LDG-1"])
        #expect(result["files"]?.numberValue == 3)
        #expect(result["moved"]?.numberValue == 5)
        #expect(Set(CardHistoryFormat.changedFiles(for: card).map(\.path)) == ["a.swift", "b.swift", "c.swift"])
        #expect(events(card, .commit).count == 1)
        #expect(events(card, .note).isEmpty)
        #expect(events(card, .sessionFiled).count == 1)
        #expect(card.status == .idea)
        #expect(card.updatedAt == updatedAt)
        #expect((card.cardSessions ?? []).isEmpty)
        #expect(CardHistoryFormat.lines(for: card).first?.text == "이전 세션 작업 연결 · 파일 3개")
    }

    @Test func errors() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let other = makeProject(ctx, key: "OTH", name: "other")
        other.makeCard(in: ctx, title: "남의 카드", at: t0)
        endedSession(ctx, p, id: "abcdef12-0000", at: t0)
        endedSession(ctx, p, id: "abcdef12-1111", at: t0)
        makeSession(ctx, p, id: "livelive-0000", startedAt: t0)
        let attached = endedSession(ctx, p, id: "attached-0000", at: t0)
        let card = p.makeCard(in: ctx, title: "카드", status: .next, at: t0)
        CardLifecycle.attach(card, attached, at: t0 - 10, in: ctx)
        let status = card.status
        let t = tools(ctx, at: t0 + 60)
        func message(_ args: JSONValue) -> String {
            do { _ = try t.call("work_file", args); return "" } catch let e as MCPToolError { return e.message } catch { return "\(error)" }
        }
        #expect(message(["sessionId": "nope"]) == "세션 없음: nope")
        #expect(message(["sessionId": "abcdef12"]).hasPrefix("짧은 ID가 여러 세션과 맞음"))
        #expect(message(["sessionId": "livelive"]).hasPrefix("끝나지 않은 세션"))
        #expect(message(["sessionId": "attached-0000"]).hasPrefix("카드에 연결된 적 있는 세션"))
        #expect(message(["sessionId": "abcdef12-0000", "cardId": "OTH-1"]) == "세션과 카드의 프로젝트가 다름")
        #expect(message(["sessionId": "abcdef12-0000", "cardId": "LDG-99"]) == "카드 없음: LDG-99")
        #expect(message(["sessionId": "abcdef12-0000", "cardId": "bad"]).hasPrefix("카드 ID 형식이 아님"))
        #expect(card.status == status)
    }

    @Test func toolsAreListed() {
        let names = MCPTools.definitions.map(\.name)
        #expect(names.contains("project_status") && names.contains("work_file"))
    }
}

@Suite struct TrackingCoverageTests {
    @Test func computesRatesAndStatusAge() throws {
        let (c, ctx) = try makeContext(); _ = c
        let p = makeProject(ctx)
        let q = makeProject(ctx, key: "QRS", name: "q")
        let archived = makeProject(ctx, key: "ARC", name: "a")
        archived.archivedAt = t0
        let now = t0 + 40 * day
        let card = p.makeCard(in: ctx, title: "카드", status: .next, at: t0)

        // 연결: 파일 있는 세션 4개 중 카드 2(하나는 메모 남김) + 정리 1, 정리 안 됨 1
        let noted = endedSession(ctx, p, id: "noted", at: now - day)
        CardLifecycle.attach(card, noted, at: now - day - 500, in: ctx)
        _ = try tools(ctx, at: now - day - 200).call("card_handoff", ["id": "LDG-1", "nextSessionNote": "다음"])
        let silent = endedSession(ctx, p, id: "silent", at: now - 2 * day)
        CardLifecycle.attach(card, silent, at: now - 2 * day - 500, in: ctx)
        endedSession(ctx, p, id: "filed", at: now - 3 * day)
        Event.record(.sessionFiled, in: ctx, project: p, at: now, payload: ["sessionId": "filed", "outcome": "dismissed"])
        endedSession(ctx, p, id: "loose", at: now - 4 * day)
        // 카드만 붙고 파일 없음: 메모 갱신률에만 든다(조건 체크 변경)
        let talk = endedSession(ctx, p, id: "talk", at: now - 5 * day, files: [])
        CardLifecycle.attach(card, talk, at: now - 5 * day - 500, in: ctx)
        card.criteria = [Criterion("x", isDone: true)]
        CardEditing.recordCriteriaChanges(card, from: [Criterion("x")], at: now - 5 * day - 100, in: ctx)
        // 기간 밖·끝나지 않음·보관 프로젝트는 세지 않는다
        endedSession(ctx, p, id: "old", at: now - 31 * day)
        let live = endedSession(ctx, p, id: "live", at: now - day); live.endedAt = nil
        endedSession(ctx, archived, id: "arch", at: now - day)
        _ = try tools(ctx, at: now - 3 * day - 3600).call("project_status", ["project": "QRS", "text": "상황"])

        let coverage = TrackingCoverage.compute(in: ctx, now: now)
        #expect(coverage.rows.map(\.key) == ["LDG", "QRS"])
        let ldg = try #require(coverage.rows.first)
        #expect((ldg.workedSessions, ldg.linkedSessions, ldg.attachedSessions, ldg.notedSessions) == (4, 3, 3, 2))
        #expect(ldg.statusAgeDays == nil)
        #expect(coverage.rows.last?.statusAgeDays == 3)
        #expect(coverage.diagnosticLines() == [
            "자동 갱신 (최근 30일)",
            "전체: 카드 연결 3/4 · 메모 갱신 2/3",
            "LDG: 카드 연결 3/4 · 메모 갱신 2/3 · 상황 없음",
            "QRS: 카드 연결 0/0 · 메모 갱신 0/0 · 상황 3일 전",
        ])
        #expect(coverage.json["projects"]?.arrayValue?.first?["linkRate"]?.numberValue == 0.75)
        #expect(coverage.json["projects"]?.arrayValue?.last?["noteRate"] == .null)
        #expect(coverage.panelLines() == ["최근 30일 · 카드 연결 3/4 · 메모 갱신 2/3", "지금 상황 · 7일 안에 갱신 1/2 프로젝트"])
        let diagnostic = IntegrationDiagnostic.text(
            version: "1", environment: "Dev", operatingSystem: "macOS", port: 47822, serverReady: true,
            history: IntegrationHistory(), installations: [:], queue: IntegrationQueue(),
            checkedAt: now, coverage: coverage)
        #expect(diagnostic.contains("\n자동 갱신 (최근 30일)\n전체: 카드 연결 3/4 · 메모 갱신 2/3\nLDG: "))
        #expect(!diagnostic.contains("가계부 앱"))
    }

    @Test func criteriaUpdateLeavesNoteOnlyForChanges() throws {
        let h = try MCPHarness()
        _ = try h.ok("card_create", ["project": "PRB", "title": "카드", "criteria": ["하나", "둘"]])
        _ = try h.ok("card_update", ["id": "PRB-1", "criteria": [["text": "하나", "done": true], ["text": "둘"], ["text": "셋"]]])
        let card = try #require(h.card(1))
        let notes = events(card, .note).map { $0.payloadValues }
        #expect(notes.count == 1)
        #expect(notes.first?["text"] == "하나")
        #expect(notes.first?["kind"]?.stringValue == CardEditing.criterionNoteKind)
    }

    @Test func emptyDiagnostic() {
        #expect(TrackingCoverage(rows: []).diagnosticLines() == ["자동 갱신 (최근 30일)", "기록 없음"])
        #expect(TrackingCoverage(rows: []).panelLines().isEmpty)
    }
}
