import Foundation
import Testing
@testable import WaypointKit

/// 이 Mac에 깔린 연동을 그대로 인식하는가(완료 조건 3). 실제 설정 파일을 **읽기만 해서** 임시 홈에 복사하고 계획을 만든다.
/// 실제 `~/.claude`·`~/.codex`·`~/.claude.json`에는 쓰지 않는다. `~/.claude.json`은 `mcpServers`만 옮긴다.
/// 연동이 깔려 있지 않은 Mac에서는 건너뛴다.
@Suite struct RealInstallStateTests {
    static let realHome = IntegrationFile.resolved(NSHomeDirectory())

    static var claudeInstalled: Bool {
        (try? String(contentsOfFile: realHome + "/.claude/settings.json", encoding: .utf8))?.contains("waypoint-hook.sh") == true
    }

    static var codexInstalled: Bool {
        FileManager.default.fileExists(atPath: realHome + "/.codex/waypoint/install.json")
    }

    private func copy(_ relative: String, into box: InstallSandbox) {
        let source = Self.realHome + "/" + relative
        let disk = IntegrationFile.read(source)
        guard let data = disk.data else { return }
        let target = box.path(relative)
        try? FileManager.default.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? IntegrationFile.apply(path: target, data: data, mode: disk.mode ?? 0o600)
    }

    private func describe(_ plan: IntegrationPlan) -> String {
        (plan.files.map { "\($0.summary): \($0.path)" } + plan.commands.map { "\($0)" } + plan.notes.map { "\($0.step): \($0.reason)" })
            .joined(separator: "\n")
    }

    @Test(.enabled(if: claudeInstalled, "이 Mac에 Claude 연동 없음"))
    func realClaudeInstallNeedsNoChange() throws {
        let box = InstallSandbox()
        for path in [".claude/settings.json", ".claude/waypoint/waypoint-hook.sh", ".claude/waypoint/waypoint-statusline-tap.sh",
                     ".claude/skills/tracker/SKILL.md"] {
            copy(path, into: box)
        }
        // ~/.claude.json은 크고 비밀 값이 있을 수 있어 mcpServers만 옮긴다
        if let data = FileManager.default.contents(atPath: Self.realHome + "/.claude.json"),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let servers = root["mcpServers"] ?? [:]
            let minimal = try JSONSerialization.data(withJSONObject: ["mcpServers": servers])
            box.write(".claude.json", String(decoding: minimal, as: UTF8.self), mode: 0o600)
        }
        let plan = try IntegrationInstaller.plan(.claude, .install, context: box.context(commandHome: Self.realHome))
        #expect(plan.isEmpty, "\(describe(plan))")
        #expect(plan.notes.isEmpty, "\(describe(plan))")
    }

    @Test(.enabled(if: codexInstalled, "이 Mac에 Codex 연동 없음"))
    func realCodexInstallNeedsNoChange() throws {
        let box = InstallSandbox()
        for path in [".codex/hooks.json", ".codex/config.toml", ".codex/waypoint/install.json",
                     ".codex/waypoint/waypoint-codex-hook.sh", ".codex/waypoint/waypoint-hook.sh",
                     ".agents/skills/waypoint-tracker/SKILL.md"] {
            copy(path, into: box)
        }
        let port = (try? OrderedJSON.parse(Data(contentsOf: URL(fileURLWithPath: Self.realHome + "/.codex/waypoint/install.json"))))?["port"]
        let instance: AppInstance = port == .number("47822") ? .dev : .stable
        let plan = try IntegrationInstaller.plan(.codex, .install, context: box.context(instance, commandHome: Self.realHome))
        #expect(plan.isEmpty, "\(describe(plan))")
    }
}
