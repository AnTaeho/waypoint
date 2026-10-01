#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 훅 스크립트가 outbox에 줄여 쓴 payload(SPEC 6장)로도 원본과 같은 기록이 나오는지.
/// 실제 `integration/hooks/waypoint-hook.sh`를 닫힌 포트로 실행해 outbox 줄을 얻는다(필터가 스크립트 안에 있다).
@Suite struct OutboxTrimTests {
    static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("integration/hooks/waypoint-hook.sh")

    /// 스크립트에 `input`을 넣고 outbox 한 줄을 읽는다. 줄이 없으면 nil.
    static func trimmedLine(_ input: Data, event: String, provider: AgentProvider) throws -> Outbox.Entry? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-trim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, event]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(),
            "WAYPOINT_PORT": "1", "WAYPOINT_SUPPORT_DIR": dir.path, "WAYPOINT_AGENT": provider.rawValue,
        ]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let url = dir.appendingPathComponent(Outbox.fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let line = text.split(separator: "\n").first
        else { return nil }
        return Outbox.parse(line: line)
    }

    static func provider(_ name: String) -> AgentProvider { name.contains("codex") ? .codex : .claude }

    static func eventName(_ data: Data) -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return object?["hook_event_name"] as? String ?? "Unknown"
    }

    static func allFixtures() throws -> [String] {
        let dir = try #require(Bundle.module.url(forResource: "Fixtures/hooks", withExtension: nil))
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    /// 처리기가 훅 입력에서 읽는 사실 전부(HookInput·HookParsing·preToolUse·postToolUse가 쓰는 것).
    static func facts(_ input: HookInput) -> [String] {
        let files = HookParsing.changedFiles(input).map { "\($0.path) +\($0.added) -\($0.removed)" }
        let commit = HookParsing.commit(input).map { "\($0.branch ?? "-") \($0.hash) \($0.message)" }
        let prompt = input.toolInput["prompt"] as? String ?? input.toolInput["message"] as? String ?? ""
        let refs = HookParsing.cardReferences(in: prompt).map { "\($0.key)-\($0.number)" }
        return [
            input.event, input.sessionID, input.cwd, input.agentID ?? "-", input.agentType ?? "-",
            input.source ?? "-", input.reason ?? "-", input.toolName ?? "-", input.toolUseID ?? "-",
            HookParsing.userPrompt(input) ?? "-", files.joined(separator: ","), commit ?? "-", refs.joined(separator: ","),
            input.toolInput["subagent_type"] as? String ?? input.toolInput["agent_type"] as? String ?? "-",
            input.toolInput["workdir"] as? String ?? input.toolInput["cwd"] as? String ?? "-",
        ]
    }

    @Test func everyFixtureKeepsWhatTheAppReads() throws {
        let names = try Self.allFixtures()
        #expect(names.count >= 30)
        for name in names {
            let data = try fixture(name)
            let provider = Self.provider(name)
            let event = Self.eventName(data)
            let entry = try #require(try Self.trimmedLine(data, event: event, provider: provider), "\(name)")
            #expect(entry.provider == provider, "\(name)")
            let original = try #require(HookInput(event: event, json: data, provider: provider), "\(name)")
            let trimmed = try #require(HookInput(event: entry.event, json: entry.payload, provider: entry.provider), "\(name)")
            #expect(Self.facts(trimmed) == Self.facts(original), "\(name)")
            #expect(entry.payload.count <= data.count, "\(name)")
        }
    }

    @Test func longPromptsAndContentKeepSameCounts() throws {
        // 붙여 넣은 긴 글, CRLF, 끝 줄바꿈 없는 내용, MultiEdit, 여러 조각 diff
        let pasted = "  <pasted_content id=\"1\">" + String(repeating: "가나다 ", count: 400) + "</pasted_content> 이거 봐줘"
        let cases: [(String, [String: Any])] = [
            ("UserPromptSubmit", ["session_id": "s", "cwd": "/x", "prompt": pasted]),
            ("UserPromptSubmit", ["session_id": "s", "cwd": "/x", "prompt": String(repeating: "긴 요청 ", count: 500)]),
            ("PostToolUse", ["session_id": "s", "cwd": "/x", "tool_name": "MultiEdit",
                             "tool_input": ["file_path": "/x/f", "edits": [
                                ["old_string": "a\r\nb", "new_string": "a\nb\nc"], ["old_string": "\n", "new_string": ""],
                             ]]]),
            ("PostToolUse", ["session_id": "s", "cwd": "/x", "tool_name": "Write",
                             "tool_input": ["file_path": "/x/f", "content": "a\nb\nno-trailing"],
                             "tool_response": ["type": "update", "structuredPatch": [
                                ["lines": [" a", "-b", "+B"]], ["lines": []], ["lines": ["+z", "\\ No newline"]],
                             ]]]),
            ("PreToolUse", ["session_id": "s", "cwd": "/x", "tool_name": "Agent",
                            "tool_input": ["prompt": "먼저 [TRK-24]를 보고 [ab-1] [LDG-7] 순서로", "subagent_type": "worker"]]),
        ]
        for (event, object) in cases {
            let data = try JSONSerialization.data(withJSONObject: object)
            let entry = try #require(try Self.trimmedLine(data, event: event, provider: .claude))
            let original = try #require(HookInput(event: event, json: data))
            let trimmed = try #require(HookInput(event: entry.event, json: entry.payload))
            #expect(Self.facts(trimmed) == Self.facts(original), "\(object)")
        }
    }

    /// 실측 픽스처를 원본으로 처리한 기록과, 줄인 outbox 줄로 처리한 기록이 같다(세션·파일 변경·커밋·하위 세션·lastPrompt).
    @Test func realFixturesProduceSameRecords() throws {
        let order = [
            "real-SessionStart", "real-UserPromptSubmit", "real-PreToolUse-Agent", "real-SubagentStart",
            "real-PostToolUse-Write-subagent", "real-SubagentStop", "real-UserPromptSubmit-agent-message",
            "real-PostToolUse-Write", "real-PostToolUse-Edit", "real-PostToolUse-Bash-commit", "real-PostToolUse-Bash",
            "real-PreToolUse-Agent-background", "real-Stop", "real-SessionStart-resume", "real-SessionStart-fork",
            "real-SessionEnd",
        ]
        func run(trimmed: Bool) throws -> (events: [String], sessions: [String]) {
            let (container, context) = try makeContext()
            _ = container
            let project = Project(key: "PRB", name: "훅 실측", rootPath: RealHookTests.root, createdAt: t0)
            context.insert(project)
            _ = project.makeCard(in: context, title: "실측용 카드", status: .next, at: t0)
            try context.save()
            let processor = HookProcessor(context: context, home: "/Users/antaeho", gitBranch: { _ in "master" })
            for (index, name) in order.enumerated() {
                let data = try fixture(name)
                let at = t0 + Double(index * 5)
                if trimmed {
                    let entry = try #require(try Self.trimmedLine(data, event: Self.eventName(data), provider: .claude))
                    processor.handle(event: entry.event, json: entry.payload, at: at, delivers: false)
                } else {
                    processor.handle(event: Self.eventName(data), json: data, at: at, delivers: false)
                }
            }
            let events = try context.fetch(FetchDescriptor<Event>()).map { event in
                let payload = event.payload.map { String(decoding: $0, as: UTF8.self) } ?? ""
                return "\(event.at.timeIntervalSince(t0)) \(event.typeRaw) \(event.session?.id ?? "-") #\(event.card?.number ?? 0) \(payload)"
            }.sorted()
            let sessions = try context.fetch(FetchDescriptor<Session>()).map { s in
                "\(s.id) \(s.kind) \(s.agentName ?? "-") \(s.parent?.id ?? "-") \(s.lastPrompt ?? "-") \(s.endedAt.map { "\($0.timeIntervalSince(t0))" } ?? "-") \(s.gitBranch ?? "-")"
            }.sorted()
            return (events, sessions)
        }
        let original = try run(trimmed: false)
        let trimmed = try run(trimmed: true)
        #expect(original.events.contains { $0.contains("file.changed") || $0.contains("fileChanged") })
        #expect(original.events.contains { $0.contains("c5a688e") })
        #expect(original.sessions.contains { $0.contains(RealHookTests.agentID) })
        #expect(original.sessions.contains { $0.contains("hi 라고만 답해") })
        #expect(trimmed.events == original.events)
        #expect(trimmed.sessions == original.sessions)
    }
}
#endif
