import Foundation

/// 사용자 범위의 훅만 검사한다. 신뢰 승인·프로젝트별 설정은 첫 실제 수신으로 확인한다.
public struct IntegrationInstallation: Equatable, Sendable {
    public enum State: Sendable { case ready, missing, attention }
    public let state: State
    public let detail: String
    public init(state: State, detail: String) { self.state = state; self.detail = detail }
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]

    public static func inspect(provider: AgentProvider, home: URL, port: UInt16) -> Self {
        let codex = provider == .codex
        if codex, let text = try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8), hooksDisabled(text) {
            return .init(state: .attention, detail: "Codex 설정의 features.hooks가 비활성화됨")
        }
        let config = home.appendingPathComponent(codex ? ".codex/hooks.json" : ".claude/settings.json")
        let bridgeName = codex ? "waypoint-codex-hook.sh" : "waypoint-hook.sh"
        let bridge = home.appendingPathComponent(codex ? ".codex/waypoint/\(bridgeName)" : ".claude/waypoint/\(bridgeName)")
        guard FileManager.default.fileExists(atPath: config.path) else {
            return .init(state: .missing, detail: "사용자 훅 설정 없음 · 프로젝트별 설정은 실제 수신으로 확인")
        }
        guard let data = try? Data(contentsOf: config),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return .init(state: .attention, detail: "사용자 훅 설정을 읽을 수 없거나 hooks 항목이 없음")
        }
        if root["disableAllHooks"] as? Bool == true {
            return .init(state: .attention, detail: "사용자 설정에서 모든 훅이 비활성화됨")
        }
        var missing: [String] = []
        var found = false
        for event in events + (codex ? [] : ["PostToolUseFailure"]) {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let commands = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "command" }
                .compactMap { $0["command"] as? String }.filter { $0.contains(bridgeName) }
            found = found || !commands.isEmpty
            if commands.isEmpty { missing.append(event); continue }
            if ["PreToolUse", "PostToolUse"].contains(event), groups.filter({ group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(bridgeName) == true }
            }).contains(where: { !["", "*"].contains($0["matcher"] as? String ?? "") }) {
                return .init(state: .attention, detail: "\(event) 훅이 일부 도구만 추적함 · 전체 도구 연동 설정 필요")
            }
            // 배포한 브리지의 기본 포트는 47821. 다른 포트의 설정을 정상이라 표시하지 않는다.
            if !commands.allSatisfy({ configuredPort($0) == port }) {
                return .init(state: .attention, detail: "\(event) 훅이 현재 앱 포트 \(port)와 다름")
            }
        }
        guard found else { return .init(state: .missing, detail: "사용자 설정에 Waypoint 훅 없음") }
        guard missing.isEmpty else { return .init(state: .attention, detail: "훅 누락: " + missing.joined(separator: ", ")) }
        guard FileManager.default.isExecutableFile(atPath: bridge.path) else {
            return .init(state: .attention, detail: "Waypoint 훅 실행 파일이 없거나 실행 권한이 없음")
        }
        if codex && !FileManager.default.isReadableFile(atPath: bridge.deletingLastPathComponent().appendingPathComponent("waypoint-hook.sh").path) {
            return .init(state: .attention, detail: "Codex 공통 훅 파일 없음 · 연동 설치를 다시 실행")
        }
        return .init(state: .ready, detail: "사용자 훅 설정 확인 · 신뢰 승인은 실제 수신으로 확인")
    }

    private static func configuredPort(_ command: String) -> UInt16? {
        guard let range = command.range(of: #"WAYPOINT_PORT=['\"]?([0-9]+)"#, options: .regularExpression) else {
            return command.contains("WAYPOINT_PORT=") ? nil : 47821
        }
        let value = command[range].filter(\.isNumber)
        return UInt16(value)
    }

    /// 배포 설정의 두 표기만 검사한다. TOML 전체를 해석하거나 신뢰 상태를 추측하지 않는다.
    static func hooksDisabled(_ text: String) -> Bool {
        var section = ""
        for raw in text.split(separator: "\n") {
            let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if line.hasPrefix("[") { section = line }
            guard section.isEmpty || section == "[features]" else { continue }
            let pattern = section == "[features]" ? #"^hooks\s*=\s*false\s*$"# : #"^features\.hooks\s*=\s*false\s*$"#
            if line.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }
}
