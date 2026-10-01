#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// TRK-11 핵심 회귀 시나리오. 끝마다 `Reliability.verify`로 오귀속·중복·손실 0건을 확인한다(docs/RELIABILITY.md).
@Suite struct ReliabilityScenarioTests {
    typealias W = ReliabilityWorld
    static let s1 = "11111111-1111-4111-8111-111111111111"
    static let s2 = "22222222-2222-4222-8222-222222222222"
    static let s3 = "33333333-3333-4333-8333-333333333333"
    static let agentA = "a1a1a1a1a1a1a1a1a"
    static let agentB = "b2b2b2b2b2b2b2b2b"

    // MARK: 픽스처 변형

    func start(_ w: W, _ session: String, cwd: String = W.probe) throws -> [String: Any] {
        try w.payload("real-SessionStart", session: session, cwd: cwd)
    }

    func prompt(_ w: W, _ session: String, _ text: String, id: String, cwd: String = W.probe) throws -> [String: Any] {
        try w.payload("real-UserPromptSubmit", session: session, cwd: cwd) {
            $0["prompt"] = text
            $0["prompt_id"] = id
        }
    }

    func edit(_ w: W, _ session: String, file: String, tool: String, cwd: String = W.probe,
              agent: String? = nil) throws -> [String: Any] {
        try w.payload("real-PostToolUse-Edit", session: session, cwd: cwd) {
            $0["tool_use_id"] = tool
            var input = $0["tool_input"] as? [String: Any] ?? [:]
            input["file_path"] = file
            $0["tool_input"] = input
            if let agent {
                $0["agent_id"] = agent
                $0["agent_type"] = "general-purpose"
            }
        }
    }

    func commit(_ w: W, _ session: String, sha: String, file: String, tool: String, cwd: String = W.probe) throws -> [String: Any] {
        try w.payload("real-PostToolUse-Bash-commit", session: session, cwd: cwd) {
            $0["tool_use_id"] = tool
            var response = $0["tool_response"] as? [String: Any] ?? [:]
            response["stdout"] = "[main \(sha)] probe\n 1 file changed, 1 insertion(+)"
            response["gitOperation"] = ["commit": ["sha": sha, "kind": "committed", "branch": "main"]]
            response["bashEditDiff"] = ["files": [["filePath": file, "hunks": [["lines": ["+hi"]]]]],
                                        "moreFiles": 0, "changedFiles": [file]]
            $0["tool_response"] = response
        }
    }

    func test(_ w: W, _ session: String, tool: String, cwd: String = W.probe) throws -> [String: Any] {
        try w.payload("real-PostToolUse-Bash-test", session: session, cwd: cwd) { $0["tool_use_id"] = tool }
    }

    func spawn(_ w: W, _ session: String, prompt: String, tool: String) throws -> [String: Any] {
        try w.payload("real-PreToolUse-Agent", session: session, cwd: W.probe) {
            $0["tool_use_id"] = tool
            var input = $0["tool_input"] as? [String: Any] ?? [:]
            input["prompt"] = prompt
            $0["tool_input"] = input
        }
    }

    func subagent(_ w: W, _ fixture: String, _ session: String, agent: String) throws -> [String: Any] {
        try w.payload(fixture, session: session, cwd: W.probe) { $0["agent_id"] = agent }
    }

    func record(_ type: EventType, _ session: String, _ detail: String, _ project: String?, _ card: String? = nil) -> ExpectedRecord {
        ExpectedRecord(type: type, session: session, project: project, card: card, detail: detail)
    }

    // MARK: (a) 재수신

    /// 같은 훅을 실시간으로 두 번 받고, 실시간 처리 뒤 같은 줄이 outbox로 또 들어와도(스크립트의 1초 시간 초과) 한 번만 남는다.
    @Test func sameHookRedeliveredLiveAndThroughOutbox() throws {
        let w = try W()
        let card = try w.card("PRB", title: "재수신")
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        try w.live(try start(w, s), at: t0 + 0.4)
        try w.attach(card, to: s, at: t0 + 1)

        let ask = try prompt(w, s, "노트 고쳐줘", id: "p-1")
        let change = try edit(w, s, file: W.probe + "/notes.txt", tool: "toolu_edit1")
        let commitHook = try commit(w, s, sha: "c5a688e", file: W.probe + "/hello.txt", tool: "toolu_commit1")
        let check = try test(w, s, tool: "toolu_test1")
        try w.live(ask, at: t0 + 2.3)
        try w.live(ask, at: t0 + 2.9)
        try w.live(change, at: t0 + 3.2)
        try w.live(change, at: t0 + 3.6)
        try w.live(commitHook, at: t0 + 4.5)
        try w.live(check, at: t0 + 5.5)
        // 실시간 응답이 1초를 넘겨 스크립트가 outbox에도 쓴 줄(초 단위 시각, 줄인 본문)
        for (hook, at) in [(ask, t0 + 2), (change, t0 + 3), (commitHook, t0 + 4), (check, t0 + 5)] {
            try w.appendOutbox(hook, at: at)
        }
        #expect(w.absorb().processed == 4)

        try Reliability.verify(w, records: [
            record(.note, s, "노트 고쳐줘", "PRB", "PRB-1"),
            record(.fileChanged, s, "notes.txt", "PRB", "PRB-1"),
            record(.fileChanged, s, "hello.txt", "PRB", "PRB-1"),
            record(.commit, s, "c5a688e", "PRB", "PRB-1"),
            record(.check, s, "bash test-pass.sh", "PRB", "PRB-1"),
        ], sessions: [s: "PRB"])
    }

    /// ID 없는 요청(옛 스크립트·옛 버전)은 같은 문장이 10초 안이면 재수신, 그보다 늦으면 새 요청으로 본다.
    @Test func promptWithoutIDFallsBackToTextAndShortWindow() throws {
        let w = try W()
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        let ask = try w.payload("real-UserPromptSubmit", session: s, cwd: W.probe) {
            $0["prompt"] = "계속"
            $0["prompt_id"] = nil
        }
        try w.live(ask, at: t0 + 2.6)
        try w.appendOutbox(ask, at: t0 + 2)
        w.absorb()
        try w.live(ask, at: t0 + 90)
        let notes = try w.context.fetch(FetchDescriptor<Event>()).filter { Reliability.detail($0) == "계속" }
        #expect(notes.map { ($0.at.timeIntervalSince(t0) * 10).rounded() }.sorted() == [26, 900])
    }

    /// 같은 `PreToolUse(Agent)`가 다시 들어와도 대기 항목이 쌓이지 않는다. 쌓이면 다음 서브에이전트가 앞 카드에 붙는다.
    @Test func replayedSpawnDoesNotPairNextSubagentWithOldCard() throws {
        let w = try W()
        let first = try w.card("PRB", title: "첫 하위 작업")
        let second = try w.card("PRB", title: "둘째 하위 작업")
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        let spawnFirst = try spawn(w, s, prompt: "[PRB-1] 첫 작업", tool: "toolu_spawn1")
        try w.live(spawnFirst, at: t0 + 1)
        try w.live(try subagent(w, "real-SubagentStart", s, agent: Self.agentA), at: t0 + 2)
        // 같은 PreToolUse가 늦게 실시간으로 한 번, outbox로 한 번 더
        try w.live(spawnFirst, at: t0 + 2.5)
        try w.appendOutbox(spawnFirst, at: t0 + 1)
        w.absorb()
        try w.live(try spawn(w, s, prompt: "[PRB-2] 둘째 작업", tool: "toolu_spawn2"), at: t0 + 5)
        try w.live(try subagent(w, "real-SubagentStart", s, agent: Self.agentB), at: t0 + 6)
        try w.live(try edit(w, s, file: W.probe + "/second.txt", tool: "toolu_sub2", agent: Self.agentB), at: t0 + 7)

        let b = try #require(try w.session(Self.agentB))
        #expect(b.openCardSessions.compactMap(\.card?.displayID) == ["PRB-2"])
        #expect(first.status == .active && second.status == .active)
        try Reliability.verify(w, records: [
            record(.fileChanged, Self.agentB, "second.txt", "PRB", "PRB-2"),
        ], sessions: [s: "PRB", Self.agentA: "PRB", Self.agentB: "PRB"])
    }

    /// 실시간으로 처리한 훅이 세션이 끝난 뒤 outbox로 다시 들어와도 중복도 손실도 없다.
    @Test func outboxCopyAfterSessionEndIsNeitherDuplicatedNorLost() throws {
        let w = try W()
        let card = try w.card("PRB", title: "종료 뒤 재수신")
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        try w.attach(card, to: s, at: t0 + 1)
        let change = try edit(w, s, file: W.probe + "/notes.txt", tool: "toolu_edit1")
        try w.live(change, at: t0 + 3.5)
        try w.live(try w.payload("real-SessionEnd", session: s, cwd: W.probe), at: t0 + 10)
        try w.appendOutbox(change, at: t0 + 3)
        w.absorb()

        #expect(card.status == .next)
        try Reliability.verify(w, records: [record(.fileChanged, s, "notes.txt", "PRB", "PRB-1")], sessions: [s: "PRB"])
    }

    // MARK: (b) 폴더

    /// 하위 폴더는 가장 가까운 등록 프로젝트로, 이름만 비슷한 옆 폴더·미등록 폴더는 기록하지 않고, 등록한 뒤부터 기록한다.
    @Test func subfolderNestedSiblingAndRegistrationOrder() throws {
        let w = try W()
        let card = try w.card("PRB", title: "하위 폴더")
        let (deep, kit, sibling, later) = (Self.s1, Self.s2, Self.s3, "44444444-4444-4444-8444-444444444444")
        let laterRoot = "/Users/antaeho/workspace/later-app"

        try w.live(try start(w, deep, cwd: W.probe + "/src/deep"), at: t0)
        try w.attach(card, to: deep, at: t0 + 1)
        try w.live(try edit(w, deep, file: W.probe + "/src/deep/a.txt", tool: "t-a", cwd: W.probe + "/src/deep"), at: t0 + 2)
        // PRB 세션이 따로 등록된 KIT 폴더 파일을 고쳤다: KIT 소속, PRB 카드에 섞지 않는다
        try w.live(try edit(w, deep, file: W.nested + "/Package.swift", tool: "t-b", cwd: W.probe + "/src/deep"), at: t0 + 3)
        try w.live(try start(w, kit, cwd: W.nested + "/Sources"), at: t0 + 4)
        try w.live(try start(w, sibling, cwd: W.probe + "-old"), at: t0 + 5)
        try w.live(try edit(w, sibling, file: W.probe + "-old/x.txt", tool: "t-c", cwd: W.probe + "-old"), at: t0 + 6)

        let waiting = try w.live(try start(w, later, cwd: laterRoot), at: t0 + 7)
        #expect(waiting?.isEmpty == false)
        try w.live(try prompt(w, later, "등록 전 요청", id: "p-l1", cwd: laterRoot), at: t0 + 8)
        #expect(try w.session(later) == nil)
        try w.registerProject("LTR", root: laterRoot)
        let block = try w.live(try prompt(w, later, "등록 후 요청", id: "p-l2", cwd: laterRoot), at: t0 + 20)
        #expect(block?.contains("LTR") == true)
        try w.live(try edit(w, later, file: laterRoot + "/main.swift", tool: "t-d", cwd: laterRoot), at: t0 + 21)

        try Reliability.verify(w, records: [
            record(.fileChanged, deep, "src/deep/a.txt", "PRB", "PRB-1"),
            record(.fileChanged, deep, "Package.swift", "KIT"),
            record(.note, later, "등록 후 요청", "LTR"),
            record(.fileChanged, later, "main.swift", "LTR"),
        ], sessions: [deep: "PRB", kit: "KIT", sibling: nil, later: "LTR"])
    }

    // MARK: (c) 프로젝트 전환

    /// 세션 중 `cd`로 다른 등록 프로젝트에 들어가 커밋·검증해도 시작 프로젝트의 카드에 붙지 않는다(훅 `cwd`는 Claude를 따라간다).
    @Test func cwdMovingIntoAnotherProjectKeepsCommitsAndChecksThere() throws {
        let w = try W()
        let card = try w.card("PRB", title: "시작 프로젝트")
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        try w.attach(card, to: s, at: t0 + 1)
        try w.live(try edit(w, s, file: W.other + "/x.swift", tool: "t-1", cwd: W.other), at: t0 + 2)
        try w.live(try commit(w, s, sha: "0be1111", file: W.other + "/c.swift", tool: "t-2", cwd: W.other), at: t0 + 3)
        try w.live(try test(w, s, tool: "t-3", cwd: W.other), at: t0 + 4)
        try w.live(try prompt(w, s, "다른 폴더에서 묻기", id: "p-1", cwd: W.other), at: t0 + 5)
        // 미등록 폴더로 옮긴 커밋은 기존처럼 세션 프로젝트로(미등록 시작 폴더 + session_bind 경우를 지킨다)
        try w.live(try commit(w, s, sha: "0be2222", file: W.probe + "/y.swift", tool: "t-4", cwd: W.probe), at: t0 + 6)

        // session_bind로 OTH로 전환: PRB 카드는 풀리고 앞 기록은 PRB에 남는다
        let session = try #require(try w.session(s))
        SessionProjectBinding.bind(session, to: try w.project("OTH"), at: t0 + 10, in: w.context)
        try w.context.save()
        let other = try w.card("OTH", title: "옮긴 프로젝트")
        try w.attach(other, to: s, at: t0 + 11)
        try w.live(try commit(w, s, sha: "0be3333", file: W.other + "/z.swift", tool: "t-5", cwd: W.other), at: t0 + 12)

        #expect(card.status == .next)
        try Reliability.verify(w, records: [
            record(.fileChanged, s, "x.swift", "OTH"),
            record(.fileChanged, s, "c.swift", "OTH"),
            record(.commit, s, "0be1111", "OTH"),
            record(.note, s, "다른 폴더에서 묻기", "PRB", "PRB-1"),
            record(.fileChanged, s, "y.swift", "PRB", "PRB-1"),
            record(.commit, s, "0be2222", "PRB", "PRB-1"),
            record(.fileChanged, s, "z.swift", "OTH", "OTH-1"),
            record(.commit, s, "0be3333", "OTH", "OTH-1"),
        ], sessions: [s: "OTH"])
    }

    // MARK: (d) 도구 변경

    /// 같은 원본 ID의 Claude·Codex 세션이 같은 프로젝트에서 동시에, 이어서 교대로 일해도 서로의 카드에 섞이지 않는다.
    @Test func claudeAndCodexShareProjectConcurrentlyAndInTurn() throws {
        let w = try W()
        let claudeCard = try w.card("PRB", title: "Claude 작업")
        let codexCard = try w.card("PRB", title: "Codex 작업")
        let raw = Self.s1
        let codex = "codex:" + raw
        func codexHook(_ name: String, _ edit: (inout [String: Any]) -> Void = { _ in }) throws -> [String: Any] {
            try w.payload("doc-codex-\(name)", session: raw, cwd: W.probe, edit)
        }
        try w.live(try start(w, raw), at: t0)
        try w.live(try codexHook("SessionStart"), at: t0 + 1, provider: .codex)
        try w.attach(claudeCard, to: raw, at: t0 + 2)
        try w.attach(codexCard, to: codex, at: t0 + 2)

        let patch = try codexHook("PostToolUse-apply_patch") { $0["tool_use_id"] = "call-patch-1" }
        try w.live(try edit(w, raw, file: W.probe + "/notes.txt", tool: "toolu_c1"), at: t0 + 3)
        try w.live(patch, at: t0 + 4, provider: .codex)
        try w.live(patch, at: t0 + 4.5, provider: .codex)
        try w.appendOutbox(patch, at: t0 + 4, provider: .codex)
        try w.live(try prompt(w, raw, "Claude 요청", id: "p-c1"), at: t0 + 5)
        let ask = try codexHook("UserPromptSubmit")
        try w.live(ask, at: t0 + 6, provider: .codex)
        try w.appendOutbox(ask, at: t0 + 6, provider: .codex)
        w.absorb()

        // 교대: Claude가 끝나고 Codex가 Claude 카드를 이어 받는다
        try w.live(try w.payload("real-SessionEnd", session: raw, cwd: W.probe), at: t0 + 10)
        #expect(claudeCard.status == .next)
        let codexSession = try #require(try w.session(codex))
        CardLifecycle.detach(codexCard, codexSession, at: t0 + 11, in: w.context)
        try w.attach(claudeCard, to: codex, at: t0 + 11)
        try w.live(try codexHook("PostToolUse-apply_patch") {
            $0["tool_use_id"] = "call-patch-2"
            $0["tool_input"] = ["command": "*** Begin Patch\n*** Add File: third.swift\n+x\n*** End Patch"]
            $0["tool_response"] = "Success. Updated the following files:\nA third.swift\n"
        }, at: t0 + 12, provider: .codex)

        try Reliability.verify(w, records: [
            record(.fileChanged, raw, "notes.txt", "PRB", "PRB-1"),
            record(.fileChanged, codex, "new.swift", "PRB", "PRB-2"),
            record(.fileChanged, codex, "old.swift", "PRB", "PRB-2"),
            record(.note, raw, "Claude 요청", "PRB", "PRB-1"),
            record(.note, codex, "LDG-1 파일 변경 기록을 구현해줘", "PRB", "PRB-2"),
            record(.fileChanged, codex, "third.swift", "PRB", "PRB-1"),
        ], sessions: [raw: "PRB", codex: "PRB"])
    }

    // MARK: (e) 복수 세션

    /// 같은 프로젝트의 세션 셋과 서브에이전트 둘이 섞여 들어와도 각자의 카드로만 간다.
    @Test func threeSessionsAndSubagentsInterleaved() throws {
        let w = try W()
        let cards = try (1...3).map { try w.card("PRB", title: "세션 \($0)") }
        let subCard = try w.card("PRB", title: "하위 작업")
        let ids = [Self.s1, Self.s2, Self.s3]
        for (index, id) in ids.enumerated() {
            try w.live(try start(w, id), at: t0 + Double(index))
            try w.attach(cards[index], to: id, at: t0 + 5)
        }
        var at = t0 + 10
        for round in 0..<3 {
            for (index, id) in ids.enumerated() {
                at += 0.2
                try w.live(try edit(w, id, file: W.probe + "/s\(index + 1)-r\(round).txt", tool: "t-\(index)-\(round)"), at: at)
                try w.live(try prompt(w, id, "세션 \(index + 1) 요청 \(round)", id: "p-\(index)-\(round)"), at: at + 0.1)
            }
        }
        // S2는 카드를 지정한 서브에이전트, S3는 카드 없는 서브에이전트. 시작 순서는 반대로
        try w.live(try spawn(w, Self.s2, prompt: "[PRB-4] 하위", tool: "toolu_s2"), at: t0 + 20)
        try w.live(try spawn(w, Self.s3, prompt: "카드 없이 조사", tool: "toolu_s3"), at: t0 + 20.1)
        try w.live(try subagent(w, "real-SubagentStart", Self.s3, agent: Self.agentB), at: t0 + 21)
        try w.live(try subagent(w, "real-SubagentStart", Self.s2, agent: Self.agentA), at: t0 + 21.2)
        try w.live(try edit(w, Self.s2, file: W.probe + "/sub-a.txt", tool: "t-sa", agent: Self.agentA), at: t0 + 22)
        try w.live(try edit(w, Self.s3, file: W.probe + "/sub-b.txt", tool: "t-sb", agent: Self.agentB), at: t0 + 22.1)
        try w.live(try subagent(w, "real-SubagentStop", Self.s2, agent: Self.agentA), at: t0 + 30)
        try w.live(try subagent(w, "real-SubagentStop", Self.s3, agent: Self.agentB), at: t0 + 30)
        try w.live(try w.payload("real-SessionEnd", session: Self.s1, cwd: W.probe), at: t0 + 31)

        #expect(subCard.status == .next)
        #expect(cards.map(\.status) == [.next, .active, .active])
        var records: [ExpectedRecord] = []
        for round in 0..<3 {
            for (index, id) in ids.enumerated() {
                records.append(record(.fileChanged, id, "s\(index + 1)-r\(round).txt", "PRB", "PRB-\(index + 1)"))
                records.append(record(.note, id, "세션 \(index + 1) 요청 \(round)", "PRB", "PRB-\(index + 1)"))
            }
        }
        records.append(record(.fileChanged, Self.agentA, "sub-a.txt", "PRB", "PRB-4"))
        records.append(record(.fileChanged, Self.agentB, "sub-b.txt", "PRB", "PRB-3"))
        try Reliability.verify(w, records: records, sessions: [
            Self.s1: "PRB", Self.s2: "PRB", Self.s3: "PRB", Self.agentA: "PRB", Self.agentB: "PRB",
        ])
    }

    // MARK: (f) 잠자기

    /// PID를 아는 세션은 몇 시간 잠자기 뒤에도 끝나지 않고 카드 연결을 지킨다. 깨어난 뒤 훅이 오면 다시 live.
    @Test func sleepWithKnownProcessKeepsSessionAndCard() throws {
        let w = try W()
        let card = try w.card("PRB", title: "잠자기")
        let s = Self.s1
        try w.live(try start(w, s), at: t0, pid: 4242)
        try w.attach(card, to: s, at: t0 + 1)
        try w.live(try prompt(w, s, "잠들기 전", id: "p-1"), at: t0 + 60, pid: 4242)
        let wake = t0 + 60 + 5 * 3600
        let alive: SessionSweep.Probe = { $0 == 4242 ? .init(startedAt: t0 - 100) : nil }
        #expect(w.processor.sweep(now: wake, probe: alive) == 0)
        let session = try #require(try w.session(s))
        #expect(session.endedAt == nil && card.status == .active)
        #expect(SessionRules.state(of: session, now: wake) == .stalled)

        try w.live(try w.payload("real-Stop", session: s, cwd: W.probe), at: wake + 5, pid: 4242)
        try w.live(try edit(w, s, file: W.probe + "/after.txt", tool: "t-after"), at: wake + 6, pid: 4242)
        #expect(w.processor.sweep(now: wake + 10, probe: alive) == 0)
        #expect(SessionRules.state(of: session, now: wake + 10) == .live)
        try Reliability.verify(w, records: [
            record(.note, s, "잠들기 전", "PRB", "PRB-1"),
            record(.fileChanged, s, "after.txt", "PRB", "PRB-1"),
        ], sessions: [s: "PRB"])
    }

    /// PID 없는 세션은 30분 규칙대로 추적을 만료하고 카드를 되돌린다(완료 아님). 깨어난 뒤 훅은 세션을 다시 살리지만 카드를 자동으로 잇지 않는다.
    @Test func sleepWithoutProcessExpiresThenRevivesWithoutCard() throws {
        let w = try W()
        let card = try w.card("PRB", title: "PID 없음")
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        try w.attach(card, to: s, at: t0 + 1)
        let wake = t0 + 5 * 3600
        #expect(w.processor.sweep(now: wake, probe: { _ in nil }) == 1)
        #expect(card.status == .next)
        try w.live(try edit(w, s, file: W.probe + "/after.txt", tool: "t-after"), at: wake + 5)
        let session = try #require(try w.session(s))
        #expect(session.endedAt == nil && session.openCardSessions.isEmpty)
        try Reliability.verify(w, records: [record(.fileChanged, s, "after.txt", "PRB")],
                               sessions: [s: "PRB"], starts: [s: 2])
    }

    /// 깨어날 때 outbox를 먼저 흡수하고 정리한다(`AppServices.refreshStates` 순서). 잠자는 동안 쌓인 활동이 있으면 끝내지 않는다.
    @Test func wakeAbsorbsQueuedActivityBeforeSweep() throws {
        let w = try W()
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        try w.appendOutbox(try w.payload("real-Stop", session: s, cwd: W.probe), at: t0 + 40 * 60)
        let wake = t0 + 45 * 60
        w.absorb()
        #expect(w.processor.sweep(now: wake, probe: { _ in nil }) == 0)
        #expect(try w.session(s)?.endedAt == nil)
        try Reliability.verify(w, records: [], sessions: [s: "PRB"])
    }

    // MARK: (g) 재시작

    /// 앱이 꺼진 동안 쌓인 outbox를 새 실행이 흡수하고 실시간으로 이어 간다. 끄기 직전 실시간+outbox로 겹친 줄도 한 번만.
    @Test func restartAbsorbsOutboxThenContinuesLive() throws {
        let w = try W(onDisk: true)
        _ = try w.card("PRB", title: "재시작")
        let s = Self.s1
        try w.live(try start(w, s), at: t0)
        try w.attach(try #require(try w.project("PRB").cards?.first), to: s, at: t0 + 1)
        let overlap = try edit(w, s, file: W.probe + "/before.txt", tool: "t-before")
        try w.live(overlap, at: t0 + 2.5)
        try w.appendOutbox(overlap, at: t0 + 2)

        // 앱 꺼짐: 훅은 outbox로만
        try w.appendOutbox(try spawn(w, s, prompt: "[PRB-1] 하위", tool: "toolu_off"), at: t0 + 10)
        try w.appendOutbox(try subagent(w, "real-SubagentStart", s, agent: Self.agentA), at: t0 + 11)
        try w.appendOutbox(try edit(w, s, file: W.probe + "/sub.txt", tool: "t-sub", agent: Self.agentA), at: t0 + 12)
        try w.appendOutbox(try subagent(w, "real-SubagentStop", s, agent: Self.agentA), at: t0 + 13)
        try w.appendOutbox(try prompt(w, s, "꺼진 동안 요청", id: "p-off"), at: t0 + 14)
        try w.appendOutbox(try commit(w, s, sha: "0ff1ce0", file: W.probe + "/off.txt", tool: "t-off"), at: t0 + 15)

        try w.restart()
        let result = w.absorb()
        #expect(result.processed == 7 && result.skipped == 0 && !result.retryPending)
        #expect(w.absorb().processed == 0)
        try w.live(try w.payload("real-Stop", session: s, cwd: W.probe), at: t0 + 30)
        try w.live(try edit(w, s, file: W.probe + "/after.txt", tool: "t-after"), at: t0 + 31)
        try w.live(try w.payload("real-SessionEnd", session: s, cwd: W.probe), at: t0 + 40)

        try Reliability.verify(w, records: [
            record(.fileChanged, s, "before.txt", "PRB", "PRB-1"),
            record(.fileChanged, Self.agentA, "sub.txt", "PRB", "PRB-1"),
            record(.note, s, "꺼진 동안 요청", "PRB", "PRB-1"),
            record(.fileChanged, s, "off.txt", "PRB", "PRB-1"),
            record(.commit, s, "0ff1ce0", "PRB", "PRB-1"),
            record(.fileChanged, s, "after.txt", "PRB", "PRB-1"),
        ], sessions: [s: "PRB", Self.agentA: "PRB"])
    }
}
#endif
