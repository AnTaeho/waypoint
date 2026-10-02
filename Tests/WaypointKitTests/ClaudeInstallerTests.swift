import Foundation
import Testing
@testable import WaypointKit

/// Claude Code 연동 설치기. 임시 홈과 가짜 `claude` CLI만 쓴다.
@Suite struct ClaudeInstallerTests {

    private func settings(_ box: InstallSandbox) throws -> OrderedJSON {
        try OrderedJSON.parse(box.text(".claude/settings.json") ?? "")
    }

    private func waypointCommands(_ root: OrderedJSON, _ event: String) -> [String] {
        (root["hooks"]?[event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }
            .filter(ClaudeInstallPlanner.isOurs).compactMap { $0["command"]?.stringValue }
    }

    @Test func eventsMatchSettingsExample() throws {
        let url = InstallSandbox.repository.appendingPathComponent("integration/hooks/settings.example.json")
        let example = try OrderedJSON.parse(Data(contentsOf: url))
        let pairs = try #require(example["hooks"]?.objectPairs)
        #expect(pairs.map(\.0) == ClaudeInstallPlanner.events.map(\.name))
        for (event, groups) in pairs {
            let group = try #require(groups.arrayValue?.first)
            #expect(group["matcher"]?.stringValue == ClaudeInstallPlanner.events.first { $0.name == event }?.matcher)
            #expect(group["hooks"]?.arrayValue?.first == ClaudeInstallPlanner(context: InstallSandbox().context()).handler(for: event))
        }
    }

    @Test func freshInstallReinstallAndRemove() throws {
        let box = InstallSandbox()
        box.installFakeClaude()
        let first = try box.run(.claude, .install)
        #expect(first.commandOutcomes == [.done])
        #expect(box.claudeCalls == ["mcp add --transport http --scope user waypoint http://127.0.0.1:47821/mcp"])
        let root = try settings(box)
        for (event, _) in ClaudeInstallPlanner.events {
            #expect(waypointCommands(root, event) == ["~/.claude/waypoint/waypoint-hook.sh \(event)"])
        }
        #expect(root["hooks"]?["PreToolUse"]?.arrayValue?.first?["matcher"] == .string("*"))
        #expect(root["statusLine"]?["command"] == .string("bash ~/.claude/waypoint/waypoint-statusline-tap.sh"))
        #expect(box.mode(".claude/waypoint/waypoint-hook.sh") == 0o755)
        #expect(box.mode(".claude/waypoint/waypoint-statusline-tap.sh") == 0o755)
        #expect(box.text(".claude/waypoint/waypoint-hook.sh") == (try String(contentsOf: InstallSandbox.sources.hookScript, encoding: .utf8)))
        #expect(box.text(".claude/skills/tracker/SKILL.md") == (try String(contentsOf: InstallSandbox.sources.trackerSkill, encoding: .utf8)))
        #expect(first.backupFolder != nil)

        // 다시 설치: 바뀔 것이 없다
        let again = try IntegrationInstaller.plan(.claude, .install, context: box.context())
        #expect(again.isEmpty, "\(again.files.map(\.summary)) \(again.commands)")

        let removed = try box.run(.claude, .remove)
        #expect(removed.commandOutcomes == [.done])
        #expect(box.claudeCalls.last == "mcp remove waypoint -s user")
        #expect(box.text(".claude/settings.json") == "{}\n")
        #expect(box.text(".claude/skills/tracker/SKILL.md") == nil)
        #expect(!FileManager.default.fileExists(atPath: box.path(".claude/skills/tracker")))
        // 스크립트는 남겨 열린 세션이 파일 누락으로 실패하지 않게 한다
        #expect(box.text(".claude/waypoint/waypoint-hook.sh") != nil)
        #expect(try IntegrationInstaller.plan(.claude, .remove, context: box.context()).isEmpty)
    }

    @Test func userEntriesKeepOrderAndRemoveRestoresBytes() throws {
        let box = InstallSandbox()
        box.installFakeClaude()
        let original = ClaudeSettingsSample.text(withWaypoint: false)
        box.write(".claude/settings.json", original, mode: 0o600)
        try box.run(.claude, .install)

        let root = try settings(box)
        let before = try OrderedJSON.parse(original)
        // 사용자 훅은 그 자리에, Waypoint 훅은 그 뒤에
        for (event, groups) in before["hooks"]!.objectPairs! {
            let now = root["hooks"]![event]!.arrayValue!
            #expect(Array(now.prefix(groups.arrayValue!.count)) == groups.arrayValue!)
        }
        #expect(root["hooks"]?.objectPairs?.map(\.0).prefix(6) == before["hooks"]?.objectPairs?.map(\.0).prefix(6))
        #expect(root.objectPairs?.map(\.0) == before.objectPairs?.map(\.0))
        #expect(root["statusLine"]?["command"]
                == .string("bash ~/.claude/waypoint/waypoint-statusline-tap.sh bash ~/.claude/awesome-statusline.sh"))
        #expect(root["ratio"] == .number("1.50"))
        #expect(box.mode(".claude/settings.json") == 0o600)
        #expect(box.text(".claude/settings.json")?.contains("\n    \"cleanupPeriodDays\"") == false)

        try box.run(.claude, .remove)
        #expect(box.text(".claude/settings.json") == original)
    }

    /// 완료 조건 3의 꼴: 이 Mac에 깔린 설정(matcher 없는 PreToolUse·PostToolUse, 감싼 상태줄)은 그대로 인식한다.
    @Test func currentInstallShapeIsRecognized() throws {
        let box = InstallSandbox()
        box.write(".claude/settings.json", ClaudeSettingsSample.text(withWaypoint: true))
        box.write(".claude/waypoint/waypoint-hook.sh", try String(contentsOf: InstallSandbox.sources.hookScript, encoding: .utf8), mode: 0o755)
        box.write(".claude/waypoint/waypoint-statusline-tap.sh", try String(contentsOf: InstallSandbox.sources.statusLineTap, encoding: .utf8), mode: 0o755)
        box.write(".claude/skills/tracker/SKILL.md", try String(contentsOf: InstallSandbox.sources.trackerSkill, encoding: .utf8))
        box.write(".claude.json", #"{"numStartups": 3, "mcpServers": {"waypoint": {"type": "http", "url": "http://127.0.0.1:47821/mcp"}}}"#)
        let plan = try IntegrationInstaller.plan(.claude, .install, context: box.context())
        #expect(plan.isEmpty, "\(plan.files.map(\.summary)) \(plan.commands)")
        #expect(plan.notes.isEmpty)
    }

    @Test func partialOrStaleWaypointHooksAreRepairedInPlace() throws {
        let box = InstallSandbox()
        var text = ClaudeSettingsSample.text(withWaypoint: true)
        // 옛 판: Stop 훅이 두 번, 제한 시간 없음
        text = text.replacingOccurrences(of: "\"command\": \"~/.claude/waypoint/waypoint-hook.sh Stop\",\n            \"timeout\": 2",
                                         with: "\"command\": \"~/.claude/waypoint/waypoint-hook.sh Stop\"")
        box.write(".claude/settings.json", text)
        try box.run(.claude, .install, runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        let root = try settings(box)
        #expect(waypointCommands(root, "Stop") == ["~/.claude/waypoint/waypoint-hook.sh Stop"])
        let stop = root["hooks"]!["Stop"]!.arrayValue!
        #expect(stop.count == 2)
        #expect(stop[1]["hooks"]?.arrayValue?.first?["timeout"] == .number("2"))
        // 다른 이벤트의 matcher 없는 묶음은 건드리지 않았다
        #expect(root["hooks"]!["PreToolUse"]!.arrayValue![1]["matcher"] == nil)
    }

    @Test func statusLineWrapRoundTrips() {
        let prefix = "bash ~/.claude/waypoint/waypoint-statusline-tap.sh"
        for original in ["bash ~/.claude/awesome-statusline.sh", "npx -y ccstatusline@latest",
                         #"cat | jq -r '.model.display_name' && echo "it's \"$PWD\"""#, "FOO=1 bash x.sh", "  spaced"] {
            let wrapped = StatusLineWrap.wrap(original, prefix: prefix)
            #expect(StatusLineWrap.unwrap(wrapped, home: "/Users/me") == .wrapped(original), "\(wrapped)")
        }
        #expect(StatusLineWrap.wrap("bash a.sh", prefix: prefix) == prefix + " bash a.sh")
        #expect(StatusLineWrap.wrap("a | b", prefix: prefix) == prefix + " bash -c 'a | b'")
        #expect(StatusLineWrap.unwrap(prefix, home: "/Users/me") == .wrapped(nil))
        #expect(StatusLineWrap.unwrap("bash /Users/me/.claude/waypoint/waypoint-statusline-tap.sh x", home: "/Users/me") == .wrapped("x"))
        #expect(StatusLineWrap.unwrap("my-wrapper waypoint-statusline-tap.sh", home: "/Users/me") == .unrecognized)
        #expect(StatusLineWrap.unwrap("bash ~/.claude/awesome-statusline.sh", home: "/Users/me") == .notWrapped)
    }

    @Test func complexStatusLineRestoredOnRemove() throws {
        let box = InstallSandbox()
        let command = #"cat | jq -r '.model' | sed "s/x/y/""#
        let original = "{\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \(OrderedJSON.quoted(command)),\n    \"padding\": 0\n  }\n}\n"
        box.write(".claude/settings.json", original)
        let none = ClaudeCommandRunner(executable: nil, environment: [:])
        try box.run(.claude, .install, runner: none)
        let wrapped = try settings(box)["statusLine"]?["command"]?.stringValue
        #expect(wrapped == "bash ~/.claude/waypoint/waypoint-statusline-tap.sh bash -c " + ToolLaunch.quote(command))
        try box.run(.claude, .remove, runner: none)
        #expect(box.text(".claude/settings.json") == original)
    }

    @Test func devInstanceReplacesStableEntries() throws {
        let box = InstallSandbox()
        box.installFakeClaude()
        try box.run(.claude, .install)
        try box.run(.claude, .install, .dev)
        let root = try settings(box)
        let prefix = #"WAYPOINT_PORT=47822 WAYPOINT_SUPPORT_DIR="$HOME/Library/Application Support/Waypoint-Dev" "#
        for (event, _) in ClaudeInstallPlanner.events {
            #expect(waypointCommands(root, event) == [prefix + "~/.claude/waypoint/waypoint-hook.sh \(event)"])
        }
        #expect(root["statusLine"]?["command"]
                == .string(#"WAYPOINT_SUPPORT_DIR="$HOME/Library/Application Support/Waypoint-Dev" bash ~/.claude/waypoint/waypoint-statusline-tap.sh"#))
        #expect(box.claudeCalls.suffix(2) == ["mcp remove waypoint -s user",
                                              "mcp add --transport http --scope user waypoint http://127.0.0.1:47822/mcp"])
        #expect(try IntegrationInstaller.plan(.claude, .install, context: box.context(.dev)).isEmpty)
        // Dev 상태에서 해제해도 Waypoint 항목은 모두 빠진다
        try box.run(.claude, .remove, .dev)
        #expect(try settings(box) == .object([]))
    }

    @Test func secondWriteFailureRollsEverythingBack() throws {
        let box = InstallSandbox()
        box.write(".claude/settings.json", ClaudeSettingsSample.text(withWaypoint: false), mode: 0o600)
        let before = box.snapshot()
        let context = box.context()
        let plan = try IntegrationInstaller.plan(.claude, .install, context: context)
        #expect(plan.files.count == 4)
        let calls = Counter()
        let failing = IntegrationApplier { path, data, mode in
            if calls.next() == 2 { throw CocoaError(.fileWriteNoPermission) }
            try IntegrationFile.apply(path: path, data: data, mode: mode)
        }
        #expect {
            try IntegrationInstaller.apply(plan, context: context, applier: failing,
                                           runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        } throws: { error in
            guard case .writeFailed(_, _, let rolledBack, _) = error as? IntegrationInstallError else { return false }
            return rolledBack
        }
        #expect(box.snapshot() == before)
        // 백업은 남는다(되돌린 근거)
        let folder = plan.backupFolder
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(IntegrationApplier.indexName).path))
    }

    @Test func backupHoldsOriginalsWithPrivatePermissions() throws {
        let box = InstallSandbox()
        let original = ClaudeSettingsSample.text(withWaypoint: false)
        box.write(".claude/settings.json", original)
        let result = try box.run(.claude, .install, runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        let folder = try #require(result.backupFolder)
        #expect(folder.deletingLastPathComponent().path == box.backups.path)
        #expect(InstallSandbox.mode(atPath: folder.path) == 0o700)
        #expect(InstallSandbox.mode(atPath: box.backups.path) == 0o700)
        let index = try OrderedJSON.parse(Data(contentsOf: folder.appendingPathComponent("paths.json")))
        let entries = try #require(index.arrayValue)
        #expect(entries.count == result.plan.files.count)
        let settingsEntry = try #require(entries.first { $0["path"]?.stringValue == box.path(".claude/settings.json") })
        let name = try #require(settingsEntry["file"]?.stringValue)
        #expect(String(data: try Data(contentsOf: folder.appendingPathComponent(name)), encoding: .utf8) == original)
        #expect(IntegrationFile.read(folder.appendingPathComponent(name).path).mode == 0o600)
        #expect(IntegrationFile.read(folder.appendingPathComponent("paths.json").path).mode == 0o600)
        // 없던 파일은 사본 없이 목록에만
        #expect(entries.contains { $0["file"] == .null && $0["path"]?.stringValue == box.path(".claude/skills/tracker/SKILL.md") })
    }

    @Test func missingCLIIsPartialSuccess() throws {
        let box = InstallSandbox()
        let result = try box.run(.claude, .install, runner: ClaudeCommandRunner.system(home: box.home.path,
                                                                                        processEnvironment: ["PATH": "/nonexistent"]))
        #expect(result.commandOutcomes == [.executableMissing])
        #expect(result.isPartial)
        #expect(box.text(".claude/settings.json") != nil)
        // 다시 계획하면 MCP 단계만 남는다
        let again = try IntegrationInstaller.plan(.claude, .install, context: box.context())
        #expect(again.files.isEmpty && again.commands == [.claudeMCPAdd(url: "http://127.0.0.1:47821/mcp")])
    }

    @Test func failingCLIIsReportedAndFilesStay() throws {
        let box = InstallSandbox()
        box.installFakeClaude(exitCode: 3)
        let result = try box.run(.claude, .install)
        guard case .failed(let message) = result.commandOutcomes.first else { Issue.record("실패가 아님"); return }
        #expect(message.contains("3"))
        #expect(box.text(".claude/settings.json") != nil)
    }

    @Test func foreignSkillAndMCPAreLeftAlone() throws {
        let box = InstallSandbox()
        box.installFakeClaude()
        let skill = "---\nname: tracker\ndescription: 내 시간 기록\n---\n본문\n"
        box.write(".claude/skills/tracker/SKILL.md", skill)
        box.write(".claude.json", #"{"mcpServers": {"waypoint": {"type": "http", "url": "https://example.com/mcp"}}}"#)
        let plan = try IntegrationInstaller.plan(.claude, .install, context: box.context())
        #expect(plan.commands.isEmpty)
        #expect(Set(plan.notes.map(\.step)) == ["tracker 스킬", "MCP 등록"])
        try IntegrationInstaller.apply(plan, context: box.context(), runner: box.fakeRunner)
        try box.run(.claude, .remove)
        #expect(box.text(".claude/skills/tracker/SKILL.md") == skill)
        #expect(box.claudeCalls.isEmpty)
    }

    @Test func changedAfterPlanWritesNothing() throws {
        let box = InstallSandbox()
        box.write(".claude/settings.json", "{}\n")
        let plan = try IntegrationInstaller.plan(.claude, .install, context: box.context())
        box.write(".claude/settings.json", "{\"model\": \"opus\"}\n")
        let before = box.snapshot()
        #expect(throws: IntegrationInstallError.changedSincePlan(path: box.path(".claude/settings.json"))) {
            try IntegrationInstaller.apply(plan, context: box.context(), runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        }
        #expect(box.snapshot() == before)
    }

    @Test func symlinkedSettingsAreWrittenThrough() throws {
        let box = InstallSandbox()
        box.write("dotfiles/settings.json", "{}\n")
        try FileManager.default.createDirectory(atPath: box.path(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: box.path(".claude/settings.json"), withDestinationPath: box.path("dotfiles/settings.json"))
        try box.run(.claude, .install, runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: box.path(".claude/settings.json"))) != nil)
        #expect(box.text("dotfiles/settings.json")?.contains("waypoint-hook.sh") == true)
    }

    @Test func unreadableSettingsStopBeforeWriting() {
        let box = InstallSandbox()
        box.write(".claude/settings.json", "{ not json")
        #expect(throws: IntegrationInstallError.self) {
            try IntegrationInstaller.plan(.claude, .install, context: box.context())
        }
    }

    @Test func keepsFourSpaceIndentAndMissingTrailingNewline() throws {
        let box = InstallSandbox()
        box.write(".claude/settings.json", "{\n    \"model\": \"opus\"\n}")
        try box.run(.claude, .install, runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        let text = try #require(box.text(".claude/settings.json"))
        #expect(text.hasPrefix("{\n    \"model\": \"opus\",\n    \"hooks\": {\n        \"SessionStart\""))
        #expect(!text.hasSuffix("\n"))
    }
}

/// 테스트 안에서 부른 횟수(Sendable 클로저용)
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
