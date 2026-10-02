import Foundation
@testable import WaypointKit

/// 설치기 테스트용 임시 홈. 실제 `~/.claude`·`~/.codex`에는 쓰지 않는다.
final class InstallSandbox {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let sources = IntegrationSources.repository(root: repository)

    let root: URL
    let home: URL
    let backups: URL

    /// 이름에 공백을 넣어 경로 인용을 함께 시험한다.
    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint installer \(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: IntegrationFile.resolved(base.path), isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        backups = root.appendingPathComponent("support/integration-backups", isDirectory: true)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func context(_ instance: AppInstance = .stable, commandHome: String? = nil) -> IntegrationInstallContext {
        IntegrationInstallContext(home: home, commandHome: commandHome, instance: instance, sources: Self.sources,
                                  backupRoot: backups)
    }

    func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }

    func write(_ relative: String, _ text: String, mode: UInt16 = 0o644) {
        let url = home.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! IntegrationFile.apply(path: url.path, data: Data(text.utf8), mode: mode)
    }

    func text(_ relative: String) -> String? {
        FileManager.default.contents(atPath: path(relative)).flatMap { String(data: $0, encoding: .utf8) }
    }

    func mode(_ relative: String) -> UInt16? { Self.mode(atPath: path(relative)) }

    /// 파일·폴더 권한
    static func mode(atPath path: String) -> UInt16? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.uint16Value
    }

    struct Entry: Equatable, CustomStringConvertible {
        var data: Data?
        var mode: UInt16
        var description: String { "\(data.map { String(decoding: $0, as: UTF8.self).prefix(80) } ?? "<dir>") (\(String(mode, radix: 8)))" }
    }

    /// 홈 아래 모든 파일·폴더(상대 경로 → 내용·권한). `excluding`으로 시작하는 경로는 뺀다.
    func snapshot(excluding: [String] = []) -> [String: Entry] {
        var result: [String: Entry] = [:]
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: home.path) else { return result }
        for case let relative as String in walker where !excluding.contains(where: { relative.hasPrefix($0) }) {
            let full = path(relative)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &isDir)
            let mode = Self.mode(atPath: full) ?? 0
            result[relative] = Entry(data: isDir.boolValue ? nil : fm.contents(atPath: full), mode: mode)
        }
        return result
    }

    /// 홈을 스냅숏 상태로 되돌린다(전부 지우고 다시 만든다).
    func restore(_ snapshot: [String: Entry]) {
        let fm = FileManager.default
        try? fm.removeItem(at: home)
        try! fm.createDirectory(at: home, withIntermediateDirectories: true)
        for relative in snapshot.keys.sorted() {
            let entry = snapshot[relative]!
            let full = path(relative)
            if let data = entry.data {
                try! fm.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try! IntegrationFile.apply(path: full, data: data, mode: entry.mode)
            } else {
                try! fm.createDirectory(atPath: full, withIntermediateDirectories: true)
            }
        }
        for relative in snapshot.keys where snapshot[relative]!.data == nil {
            try? fm.setAttributes([.posixPermissions: snapshot[relative]!.mode], ofItemAtPath: path(relative))
        }
    }

    /// `~/.local/bin/claude` 가짜 CLI. 인자를 `claude-calls.log`에 남기고 `~/.claude.json`의 `mcpServers`를 고친다.
    func installFakeClaude(exitCode: Int = 0) {
        write(".local/bin/claude", """
        #!/bin/bash
        echo "$*" >> "$HOME/claude-calls.log"
        [ \(exitCode) -eq 0 ] || { echo "가짜 실패" >&2; exit \(exitCode); }
        if [ "$1 $2" = "mcp add" ]; then
          printf '{"mcpServers":{"waypoint":{"type":"http","url":"%s"}}}\\n' "${@: -1}" > "$HOME/.claude.json"
        elif [ "$1 $2" = "mcp remove" ]; then
          printf '{"mcpServers":{}}\\n' > "$HOME/.claude.json"
        fi

        """, mode: 0o755)
    }

    var fakeRunner: ClaudeCommandRunner {
        ClaudeCommandRunner.system(home: home.path, processEnvironment: ["PATH": "/usr/bin:/bin"])
    }

    var claudeCalls: [String] {
        (text("claude-calls.log") ?? "").split(separator: "\n").map(String.init)
    }

    @discardableResult
    func run(_ provider: AgentProvider, _ action: IntegrationPlan.Action, _ instance: AppInstance = .stable,
             runner: ClaudeCommandRunner? = nil) throws -> IntegrationInstaller.Result {
        let context = context(instance)
        let plan = try IntegrationInstaller.plan(provider, action, context: context)
        return try IntegrationInstaller.apply(plan, context: context, runner: runner ?? fakeRunner)
    }
}

/// 이 Mac의 실제 설정과 같은 꼴(사용자의 다른 훅·상태줄·권한이 섞여 있다). 실제 파일을 복사하지 않는 고정 예.
enum ClaudeSettingsSample {
    static func userHook(_ arg: String) -> String {
        """
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "bash /Users/me/.claude/cc-hook.sh \(arg)",
                    "async": true
                  }
                ]
              }
        """
    }

    static func waypointHook(_ event: String) -> String {
        """
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "~/.claude/waypoint/waypoint-hook.sh \(event)",
                    "timeout": 2
                  }
                ]
              }
        """
    }

    static func event(_ name: String, _ groups: [String]) -> String {
        "    \"\(name)\": [\n" + groups.joined(separator: ",\n") + "\n    ]"
    }

    /// `withWaypoint`면 지금 설치 상태(PreToolUse·PostToolUse에 matcher 없음)
    static func text(withWaypoint: Bool, statusLine: String? = "bash ~/.claude/awesome-statusline.sh") -> String {
        func w(_ e: String) -> [String] { withWaypoint ? [waypointHook(e)] : [] }
        var events: [String] = [
            event("SessionStart", [userHook("idle")] + w("SessionStart")),
            event("UserPromptSubmit", [userHook("working")] + w("UserPromptSubmit")),
            event("Notification", [userHook("notify")]),
            event("Stop", [userHook("stop")] + w("Stop")),
            event("SessionEnd", [userHook("end")] + w("SessionEnd")),
            event("PreToolUse", [userHook("tool")] + w("PreToolUse")),
        ]
        if withWaypoint {
            events += ["SubagentStart", "PostToolUse", "SubagentStop", "PermissionRequest", "PostToolUseFailure"]
                .map { event($0, w($0)) }
        }
        var text = """
        {
          "cleanupPeriodDays": 14,
          "permissions": {
            "defaultMode": "auto",
            "allow": ["Bash(ls:*)"]
          },
          "hooks": {

        """
        text += events.joined(separator: ",\n") + "\n  },\n"
        if let statusLine {
            let command = withWaypoint ? "bash ~/.claude/waypoint/waypoint-statusline-tap.sh " + statusLine : statusLine
            text += """
              "statusLine": {
                "type": "command",
                "command": \(OrderedJSON.quoted(command))
              },

            """
        }
        text += """
          "enabledPlugins": {
            "swift-lsp@claude-plugins-official": true
          },
          "model": "한국어 이름 é \\"인용\\" / 슬래시",
          "ratio": 1.50
        }

        """
        // 원문 꼴 그대로가 아니면 비교가 무의미하다: 배열 한 줄 표기는 고정 예에서 빼고 쓴다
        return text.replacingOccurrences(of: "\"allow\": [\"Bash(ls:*)\"]", with: "\"allow\": [\n      \"Bash(ls:*)\"\n    ]")
    }
}
