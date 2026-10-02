import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 같은 파일 작업 중(TRK-17): 판정 규칙·저장소 색인·MCP `overlaps`·훅 `checkout`·시작 블록.
@Suite struct WorkOverlapTests {
    let now = t0 + 7200

    func touch(_ unit: String, _ path: String, checkout: String? = "/repo", ago: TimeInterval = 60,
               session: String? = nil) -> WorkOverlap.Touch {
        WorkOverlap.Touch(unit: unit, session: session ?? unit, checkout: checkout, path: path, at: now - ago)
    }

    // MARK: - 순수 판정

    @Test func sameCheckoutSameFileOverlapsBothWays() {
        let pairs = WorkOverlap.pairs([
            touch("a", "Sources/A.swift"), touch("b", "Sources/A.swift", ago: 30),
            touch("a", "Sources/B.swift"), touch("b", "README.md"),
        ], live: ["a", "b"], now: now)
        #expect(pairs == [
            .init(unit: "a", other: "b", files: ["Sources/A.swift"]),
            .init(unit: "b", other: "a", files: ["Sources/A.swift"]),
        ])
    }

    @Test func differentCheckoutIsIgnored() {
        let pairs = WorkOverlap.pairs([
            touch("a", "A.swift", checkout: "/repo"),
            touch("b", "A.swift", checkout: "/repo/.claude/worktrees/x"),
        ], live: ["a", "b"], now: now)
        #expect(pairs.isEmpty)
    }

    @Test func endedUnitIsIgnored() {
        let pairs = WorkOverlap.pairs([touch("a", "A.swift"), touch("b", "A.swift")], live: ["a"], now: now)
        #expect(pairs.isEmpty)
    }

    @Test func windowBoundaryIsInclusive() {
        let inside = WorkOverlap.pairs([touch("a", "A.swift", ago: 3600), touch("b", "A.swift")],
                                       live: ["a", "b"], now: now)
        #expect(inside.count == 2)
        let outside = WorkOverlap.pairs([touch("a", "A.swift", ago: 3601), touch("b", "A.swift")],
                                        live: ["a", "b"], now: now)
        #expect(outside.isEmpty)
    }

    @Test func sameUnitNeverOverlaps() {
        // 부모(a)와 서브에이전트(a의 sub)는 같은 단위
        let pairs = WorkOverlap.pairs([touch("a", "A.swift"), touch("a", "A.swift", session: "sub")],
                                      live: ["a"], now: now)
        #expect(pairs.isEmpty)
    }

    @Test func missingCheckoutIsIgnored() {
        let pairs = WorkOverlap.pairs([touch("a", "A.swift", checkout: nil), touch("b", "A.swift", checkout: nil)],
                                      live: ["a", "b"], now: now)
        #expect(pairs.isEmpty)
        let half = WorkOverlap.pairs([touch("a", "A.swift"), touch("b", "A.swift", checkout: nil)],
                                     live: ["a", "b"], now: now)
        #expect(half.isEmpty)
    }

    @Test func filesAreMostRecentFirst() {
        let pairs = WorkOverlap.pairs([
            touch("a", "old.swift", ago: 600), touch("b", "old.swift", ago: 500),
            touch("a", "new.swift", ago: 20), touch("b", "new.swift", ago: 400),
        ], live: ["a", "b"], now: now)
        #expect(pairs.first?.files == ["new.swift", "old.swift"])
    }

    @Test func sameOverlapIsReportedOnceAndNewFileAgain() {
        var reported: Set<String> = []
        var decision = WorkOverlap.shouldReport(["A.swift"], reported: reported)
        #expect(decision.report)
        reported = decision.reported
        decision = WorkOverlap.shouldReport(["A.swift"], reported: reported)
        #expect(!decision.report)
        decision = WorkOverlap.shouldReport(["A.swift", "B.swift"], reported: reported)
        #expect(decision.report)
        reported = decision.reported
        // 줄어든 집합은 이미 알린 것
        #expect(!WorkOverlap.shouldReport(["B.swift"], reported: reported).report)
        #expect(!WorkOverlap.shouldReport([], reported: []).report)
    }

    // MARK: - 저장소 색인

    /// 같은 프로젝트에 메인 세션 둘(a, b)과 a의 서브에이전트. 모두 최근 활동.
    struct Scene {
        let container: ModelContainer
        let context: ModelContext
        let project: Project
        let a: Session
        let b: Session
        let sub: Session

        init(now: Date) throws {
            (container, context) = try makeContext()
            project = Project(key: "PRB", name: "probe", rootPath: "/repo", createdAt: t0)
            context.insert(project)
            a = makeSession(context, project, id: "aaaaaaaa-1111", startedAt: now - 600, lastSeenAt: now - 10)
            b = makeSession(context, project, id: "bbbbbbbb-2222", startedAt: now - 600, lastSeenAt: now - 10)
            sub = makeSession(context, project, id: "cccccccc-3333", startedAt: now - 300, lastSeenAt: now - 10, parent: a)
            try context.save()
        }

        func change(_ session: Session, _ path: String, checkout: String? = "/repo", at: Date, card: Card? = nil) {
            var payload: [String: EventValue] = ["path": .string(path), "added": 1, "removed": 0]
            if let checkout { payload["checkout"] = .string(checkout) }
            Event.record(.fileChanged, in: context, project: project, card: card, session: session, at: at, payload: payload)
        }
    }

    @Test func indexFindsOverlapAndOtherCard() throws {
        let s = try Scene(now: now)
        let card = s.project.makeCard(in: s.context, title: "파서", at: t0)
        CardLifecycle.attach(card, s.b, at: now - 500, in: s.context)
        s.change(s.a, "A.swift", at: now - 100)
        s.change(s.b, "A.swift", at: now - 50, card: card)
        s.change(s.b, "A.swift", at: now - 50)  // 카드마다 한 건씩 남은 같은 변경
        s.change(s.b, "B.swift", at: now - 40, card: card)
        let index = WorkOverlap.index(for: s.project, now: now)
        let seenByA = index.overlaps(for: s.a)
        #expect(seenByA.map(\.files) == [["A.swift"]])
        #expect(seenByA.first?.other === s.b)
        #expect(seenByA.first?.label == "PRB-1")
        #expect(WorkOverlap.summary(seenByA) == "같은 파일 1개 · PRB-1")
        #expect(index.overlaps(for: s.b).first?.other === s.a)
        #expect(index.overlaps(for: s.b).first?.label == "sess·aaaa")
        #expect(index.recentFiles(of: s.b) == ["B.swift", "A.swift"])
    }

    @Test func subagentCountsForItsParentButNotAgainstIt() throws {
        let s = try Scene(now: now)
        s.change(s.sub, "A.swift", at: now - 100)
        s.change(s.a, "A.swift", at: now - 90)
        #expect(WorkOverlap.index(for: s.project, now: now).isEmpty)  // 부모-서브에이전트는 겹침 아님

        s.change(s.b, "A.swift", at: now - 50)
        s.change(s.a, "Only.swift", at: now - 40)
        s.change(s.b, "Only.swift", at: now - 30)
        let index = WorkOverlap.index(for: s.project, now: now)
        #expect(index.overlaps(for: s.a).first?.files == ["Only.swift", "A.swift"])
        // 서브에이전트 줄은 그 세션이 바꾼 파일만
        #expect(index.overlaps(for: s.sub).first?.files == ["A.swift"])
        #expect(index.overlaps(for: s.b).first?.other === s.a)
    }

    @Test func endedSessionDropsOverlap() throws {
        let s = try Scene(now: now)
        s.change(s.a, "A.swift", at: now - 100)
        s.change(s.b, "A.swift", at: now - 50)
        #expect(!WorkOverlap.index(for: s.project, now: now).overlaps(for: s.a).isEmpty)
        s.b.endedAt = now - 5
        #expect(WorkOverlap.index(for: s.project, now: now).overlaps(for: s.a).isEmpty)
    }

    @Test func worktreeAndOldRecordsDoNotWarn() throws {
        let s = try Scene(now: now)
        s.change(s.a, "A.swift", at: now - 100)
        s.change(s.b, "A.swift", checkout: "/repo/.claude/worktrees/x", at: now - 50)
        s.change(s.a, "Old.swift", checkout: nil, at: now - 100)
        s.change(s.b, "Old.swift", checkout: nil, at: now - 50)
        let index = WorkOverlap.index(for: s.project, now: now)
        #expect(index.isEmpty)
        // 블록용 최근 파일은 체크아웃을 몰라도 보인다
        #expect(index.recentFiles(of: s.b) == ["A.swift", "Old.swift"])
    }

    @Test func situationCountsOverlapFiles() throws {
        let s = try Scene(now: now)
        let card = s.project.makeCard(in: s.context, title: "파서", at: t0)
        CardLifecycle.attach(card, s.b, at: now - 500, in: s.context)
        s.change(s.a, "A.swift", at: now - 100)
        s.change(s.b, "A.swift", at: now - 50, card: card)
        let tile = ProjectSituation.make(for: s.project, now: now, status: nil, unfiledCount: 0)
        #expect(tile.inProgress.first?.overlapFileCount == 1)
    }

    // MARK: - MCP

    @Test func mcpReportsOverlapOnceAndAgainForNewFile() throws {
        let h = try MCPHarness()
        let date = t0 + 60
        let other = makeSession(h.context, h.project, id: "dddddddd-4444", startedAt: t0, lastSeenAt: t0 + 50)
        other.provider = .codex
        func change(_ session: Session, _ path: String, at offset: TimeInterval) {
            Event.record(.fileChanged, in: h.context, project: h.project, session: session, at: date - offset,
                         payload: ["path": .string(path), "checkout": "/Users/me/probe"])
        }
        h.session.lastSeenAt = date
        change(h.session, "A.swift", at: 30)
        change(other, "A.swift", at: 20)
        let sid = JSONValue.string(MCPHarness.sessionID)
        _ = try h.ok("card_create", ["project": "PRB", "title": "파서", "sessionId": sid])
        let started = try h.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        let overlaps = try #require(started["overlaps"]?.arrayValue)
        #expect(overlaps.count == 1)
        #expect(overlaps.first?["sessionId"]?.stringValue == "codex:dddddddd")
        #expect(overlaps.first?["provider"]?.stringValue == "codex")
        #expect(overlaps.first?["files"] == ["A.swift"])
        #expect(overlaps.first?["fileCount"] == JSONValue(1))

        // 같은 겹침은 응답마다 반복하지 않는다(세션 ID 없는 도구는 카드의 세션으로 본다)
        #expect(try h.ok("card_note", ["id": "PRB-1", "text": "메모"])["overlaps"] == nil)
        #expect(try h.ok("project_status", ["project": "PRB", "text": "상황", "sessionId": sid])["overlaps"] == nil)
        #expect(try h.ok("card_handoff", ["id": "PRB-1", "nextSessionNote": "다음"])["overlaps"] == nil)

        // 새 파일이 겹치면 다시
        change(h.session, "B.swift", at: 10)
        change(other, "B.swift", at: 5)
        let again = try h.ok("card_note", ["id": "PRB-1", "text": "또"])
        #expect(again["overlaps"]?.arrayValue?.first?["files"] == ["B.swift", "A.swift"])
        #expect(try h.ok("card_evidence", ["id": "PRB-1", "command": "swift test", "outcome": "pass"])["overlaps"] == nil)
    }

    @Test func mcpWithoutOverlapAddsNothing() throws {
        let h = try MCPHarness()
        let sid = JSONValue.string(MCPHarness.sessionID)
        _ = try h.ok("card_create", ["project": "PRB", "title": "파서", "sessionId": sid])
        let started = try h.ok("card_start", ["id": "PRB-1", "sessionId": sid])
        #expect(started["overlaps"] == nil)
        #expect(started["otherSessions"] == [])
    }

    // MARK: - 훅 `checkout`

    @Test func hookRecordsCheckoutRootIncludingWorktree() throws {
        let fm = FileManager.default
        let repo = fm.temporaryDirectory.appendingPathComponent("waypoint-overlap-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: repo) }
        let worktree = repo.appendingPathComponent(".claude/worktrees/x")
        try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: worktree.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/x\n".write(to: worktree.appendingPathComponent(".git"),
                                                             atomically: true, encoding: .utf8)
        #expect(GitInfo.checkoutRoot(for: repo.appendingPathComponent("Sources/A.swift").path) == repo.path)
        #expect(GitInfo.checkoutRoot(for: worktree.appendingPathComponent("Sources/A.swift").path) == worktree.path)
        #expect(GitInfo.checkoutRoot(for: "/nonexistent-waypoint/a.swift") == nil)
        #expect(GitInfo.checkoutRoot(for: "relative/a.swift") == nil)

        let (container, context) = try makeContext()
        _ = container
        let project = Project(key: "PRB", name: "probe", rootPath: repo.path, createdAt: t0)
        context.insert(project)
        try context.save()
        let processor = HookProcessor(context: context, home: "/Users/me", gitBranch: { _ in "main" })
        func edit(_ session: String, _ file: URL, cwd: URL, at date: Date) {
            let body: [String: Any] = [
                "session_id": session, "hook_event_name": "PostToolUse", "cwd": cwd.path,
                "tool_name": "Edit", "tool_use_id": UUID().uuidString,
                "tool_input": ["file_path": file.path, "old_string": "a", "new_string": "b"],
            ]
            processor.handle(event: nil, json: try! JSONSerialization.data(withJSONObject: body), at: date)
        }
        edit("main-1", repo.appendingPathComponent("Sources/A.swift"), cwd: repo, at: now - 100)
        edit("tree-2", worktree.appendingPathComponent("Sources/A.swift"), cwd: worktree, at: now - 90)
        edit("main-3", repo.appendingPathComponent("Sources/A.swift"), cwd: repo, at: now - 80)
        let changes = try context.fetch(FetchDescriptor<Event>()).filter { $0.type == .fileChanged }
            .map { ($0.session?.id ?? "", $0.payloadValues["path"]?.stringValue ?? "", $0.payloadValues["checkout"]?.stringValue) }
            .sorted { $0.0 < $1.0 }
        #expect(changes.map(\.0) == ["main-1", "main-3", "tree-2"])
        #expect(changes.map(\.1) == ["Sources/A.swift", "Sources/A.swift", ".claude/worktrees/x/Sources/A.swift"])
        #expect(changes.map(\.2) == [repo.path, repo.path, worktree.path])

        let sessions = try context.fetch(FetchDescriptor<Session>())
        for session in sessions { session.lastSeenAt = now - 10 }
        let index = WorkOverlap.index(for: project, now: now)
        let main1 = try #require(sessions.first { $0.id == "main-1" })
        let tree = try #require(sessions.first { $0.id == "tree-2" })
        #expect(index.overlaps(for: main1).map(\.other.id) == ["main-3"])
        #expect(index.overlaps(for: tree).isEmpty)
    }

    // MARK: - 시작 블록

    @Test func sessionStartBlockShowsOtherSessionsRecentFiles() throws {
        let s = try Scene(now: now)
        let card = s.project.makeCard(in: s.context, title: "파서", at: t0)
        CardLifecycle.attach(card, s.b, at: now - 500, in: s.context)
        s.change(s.b, "Parser.swift", at: now - 50, card: card)
        s.change(s.b, "Lexer.swift", at: now - 40, card: card)
        s.change(s.b, "Token.swift", at: now - 30, card: card)
        s.change(s.b, "Old.swift", at: now - 20, card: card)
        let fresh = makeSession(s.context, s.project, id: "eeeeeeee-5555", startedAt: now, lastSeenAt: now)
        let text = SessionContext.text(project: s.project, session: fresh, now: now)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("- PRB-1 ") })
        #expect(line.hasSuffix(" · 최근 파일: Old.swift, Token.swift, Lexer.swift"))
    }
}

/// 실제 저장소 **사본**으로 겹침 색인·시작 블록 시간을 잰다. `WAYPOINT_REAL_STORE_COPY`(사본 `.store` 경로)가 있을 때만 돈다.
@Suite struct WorkOverlapTimingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"] != nil))
    func realStoreOverlapTiming() throws {
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WAYPOINT_REAL_STORE_COPY"]!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-overlap-\(UUID().uuidString)")
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
        let projects = try ctx.fetch(FetchDescriptor<Project>()).filter { $0.archivedAt == nil }
        // 사본의 마지막 기록 시각을 「지금」으로 본다(최근 60분 변경이 있게)
        let now = projects.compactMap(\.lastEventAt).max() ?? Date()

        func median(_ runs: Int, _ body: () -> Void) -> Double {
            let times = (0..<runs).map { _ -> Double in
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }.sorted()
            return times[times.count / 2]
        }
        let rows = projects.flatMap { DashboardQuery.rows(for: $0, now: now) }
        _ = WorkOverlap.byRow(rows, now: now)
        let index = median(20) { for p in projects { _ = WorkOverlap.index(for: p, now: now) } }
        let byRow = median(20) { _ = WorkOverlap.byRow(rows, now: now) }
        let fresh = Session(id: "timing-\(UUID().uuidString)", startedAt: now, lastSeenAt: now)
        ctx.insert(fresh)
        let block = median(20) { for p in projects { _ = SessionContext.text(project: p, session: fresh, now: now) } }
        let pairs = projects.map { WorkOverlap.index(for: $0, now: now) }.filter { !$0.isEmpty }.count
        print("[overlap-timing] projects=\(projects.count) sessions=\(try ctx.fetchCount(FetchDescriptor<Session>())) "
              + "events=\(try ctx.fetchCount(FetchDescriptor<Event>())) rows=\(rows.count) projectsWithOverlap=\(pairs) "
              + String(format: "indexAll=%.2fms byRow=%.2fms blockAll=%.2fms", index, byRow, block))
    }
}
