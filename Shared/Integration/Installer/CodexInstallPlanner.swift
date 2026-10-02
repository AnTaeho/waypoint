import CryptoKit
import Foundation

/// Codex 연동 계획. `scripts/install-codex.py`를 그대로 옮겼다(같은 입력이면 같은 바이트를 쓴다. 테스트가 비교한다).
/// 다른 점: 백업은 Waypoint 저장 폴더(`integration-backups/`)에 남기고, 바뀔 것이 없으면 아무것도 쓰지 않는다
/// (파이썬은 매번 다시 쓰고 `install.json`의 백업 경로를 바꾼다).
/// 대상: `~/.codex/hooks.json`, `~/.codex/config.toml`(표시한 MCP 블록), `~/.codex/waypoint/`(브리지·공통 훅·
/// `install.json`), `~/.agents/skills/waypoint-tracker/SKILL.md`. 신뢰 상태(`[hooks.state]`)는 바꾸지 않는다.
struct CodexInstallPlanner {
    let context: IntegrationInstallContext

    static let begin = "# BEGIN WAYPOINT MCP (managed by install-codex.py)"
    static let end = "# END WAYPOINT MCP"
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                         "SubagentStart", "SubagentStop", "Stop", "Interrupt", "SessionEnd"]
    static let scriptMode: UInt16 = 0o700

    var codexDir: String { context.path(".codex") }
    var hooksPath: String { context.path(".codex/hooks.json") }
    var configPath: String { context.path(".codex/config.toml") }
    var integrationDir: String { context.path(".codex/waypoint") }
    var bridgePath: String { context.path(".codex/waypoint/waypoint-codex-hook.sh") }
    var commonHookPath: String { context.path(".codex/waypoint/waypoint-hook.sh") }
    var skillPath: String { context.path(".agents/skills/waypoint-tracker/SKILL.md") }
    var manifestPath: String { context.path(".codex/waypoint/install.json") }
    /// 훅 명령에 적는 브리지 경로
    var bridgeInCommand: String { context.commandHome + "/.codex/waypoint/waypoint-codex-hook.sh" }

    func plan(_ action: IntegrationPlan.Action) throws -> IntegrationPlan {
        let remove = action == .remove
        let home = context.commandHome
        // 셸 이중 따옴표 안에 경로를 넣는다. 셸 확장 문자가 있는 홈은 거절한다.
        if home.contains(where: { "\"$`\\\n\r".contains($0) }) {
            throw IntegrationInstallError.conflict("홈 경로에 셸 확장 문자가 있어 설정할 수 없습니다")
        }
        let originalHooks = try Self.readText(hooksPath)
        let originalConfig = try Self.readText(configPath)
        var hooks: OrderedJSON
        let config: MiniTOML
        do {
            hooks = try OrderedJSON.parse((originalHooks?.isEmpty ?? true) ? "{}" : originalHooks!)
        } catch {
            throw IntegrationInstallError.unreadable(path: hooksPath, reason: "JSON이 아님")
        }
        do { config = try MiniTOML(originalConfig ?? "") } catch {
            throw IntegrationInstallError.unreadable(path: configPath, reason: "TOML이 아님")
        }
        guard hooks.objectPairs != nil, hooks["hooks"] == nil || hooks["hooks"]?.objectPairs != nil else {
            throw IntegrationInstallError.unreadable(path: hooksPath, reason: "기존 hooks.json 구조를 확인하세요")
        }
        var manifest = OrderedJSON.object([])
        if let text = try Self.readText(manifestPath) {
            guard let parsed = try? OrderedJSON.parse(text), parsed.objectPairs != nil else {
                throw IntegrationInstallError.unreadable(path: manifestPath, reason: "JSON 객체가 아님")
            }
            manifest = parsed
        }
        let skill = Self.replacingFirst(Self.normalized(try context.sources.text(context.sources.trackerSkill)),
                                        "name: tracker\n", with: "name: waypoint-tracker\n")
        let oldSkill = try Self.readText(skillPath)
        let oldHash = oldSkill.map(Self.sha256)
        let manifestHashMatches = oldHash.map { manifest["skillHash"] == .string($0) } ?? (manifest["skillHash"] == nil)
        if !remove, let oldSkill, oldSkill != skill, !manifestHashMatches {
            throw IntegrationInstallError.conflict("waypoint-tracker 스킬이 이미 있고 직접 수정됨. 기존 파일을 보존합니다")
        }
        let port = context.port
        let url = context.mcpURL
        var cleanedConfig = Self.removingBlocks(originalConfig ?? "")
        let remaining: MiniTOML
        do { remaining = try MiniTOML(cleanedConfig) } catch {
            throw IntegrationInstallError.unreadable(path: configPath, reason: "TOML이 아님")
        }
        let serverPath = ["mcp_servers", "waypoint"]
        let existing = remaining.contains(serverPath)
        if !remove, existing, remaining.flatTable(serverPath) != ["url": .string(url)] {
            throw IntegrationInstallError.conflict("기존 waypoint MCP 설정이 다릅니다. 기존 설정을 보존합니다")
        }
        var installedHooks = try withoutOurs(hooks["hooks"]?.objectPairs ?? [])
        if !remove {
            let support = context.instance.supportFolderName
            for event in Self.events {
                let command = "WAYPOINT_PORT=\(port) WAYPOINT_SUPPORT_DIR=\"\(home)/Library/Application Support/\(support)\" "
                    + "bash \"\(bridgeInCommand)\" \(event)"
                var handler: [(String, OrderedJSON)] = [("type", .string("command")), ("command", .string(command)),
                                                        ("timeout", .number("2"))]
                if event == "SessionStart" || event == "UserPromptSubmit" {
                    handler.append(("additionalContextLimit", .number("1500")))
                }
                let group = OrderedJSON.object([("hooks", .array([.object(handler)]))])
                if let index = installedHooks.firstIndex(where: { $0.0 == event }) {
                    installedHooks[index].1 = .array((installedHooks[index].1.arrayValue ?? []) + [group])
                } else {
                    installedHooks.append((event, .array([group])))
                }
            }
            if !existing {
                cleanedConfig = Self.pythonRstrip(cleanedConfig)
                    + "\n\n\(Self.begin)\n[mcp_servers.waypoint]\nurl = \"\(url)\"\n\(Self.end)\n"
            }
        }
        hooks = hooks.setting("hooks", installedHooks.isEmpty ? nil : .object(installedHooks))
        do { _ = try MiniTOML(cleanedConfig) } catch {
            throw IntegrationInstallError.unreadable(path: configPath, reason: "고친 TOML을 읽을 수 없음")
        }
        if config.leaf(["features", "hooks"]) == .other("false") && !remove {
            throw IntegrationInstallError.conflict("Codex 설정에서 features.hooks=false입니다. 훅 사용 설정을 먼저 확인하세요")
        }

        var plan = IntegrationPlan(provider: .codex, action: remove ? .remove : .install, files: [], commands: [],
                                   notes: [], backupFolder: IntegrationApplier.backupFolder(root: context.backupRoot, at: context.now))
        let hooksText = Self.jsonText(hooks)
        if remove {
            if hooks.objectPairs?.isEmpty == false {
                plan.set(hooksPath, to: Data(hooksText.utf8), mode: nil, summary: "Codex 훅 연결 해제")
            } else {
                plan.set(hooksPath, to: nil, mode: nil, summary: "Codex 훅 설정 지움")
            }
            if originalConfig != nil {
                plan.set(configPath, to: Data(cleanedConfig.utf8), mode: nil, summary: "MCP 블록 지움")
            }
            if oldSkill != nil, manifestHashMatches {
                plan.set(skillPath, to: nil, mode: nil, summary: "waypoint-tracker 스킬 지움")
            }
            // 훅 스크립트·install.json·백업은 남겨 진행 중인 세션이 파일 누락으로 실패하지 않게 한다.
        } else {
            let common = Self.normalized(try context.sources.text(context.sources.hookScript))
            let bridge = Self.normalized(try context.sources.text(context.sources.codexBridge))
            plan.set(commonHookPath, to: Data(common.utf8), mode: Self.scriptMode, summary: "공통 훅 스크립트")
            plan.set(bridgePath, to: Data(bridge.utf8), mode: Self.scriptMode, summary: "Codex 브리지")
            plan.set(skillPath, to: Data(skill.utf8), mode: nil, summary: "waypoint-tracker 스킬")
            plan.set(configPath, to: Data(cleanedConfig.utf8), mode: nil, summary: "MCP 블록")
            plan.set(hooksPath, to: Data(hooksText.utf8), mode: nil, summary: "Codex 훅 연결")
            let skillHash = Self.sha256(skill)
            let manifestCurrent = manifest["skillHash"] == .string(skillHash) && manifest["port"] == .number(String(port))
            if !plan.files.isEmpty || !manifestCurrent {
                let text = Self.jsonText(.object([("skillHash", .string(skillHash)), ("port", .number(String(port))),
                                                  ("backup", .string(plan.backupFolder.path))]))
                plan.set(manifestPath, to: Data(text.utf8), mode: nil, summary: "설치 기록")
            }
        }
        return plan
    }

    // MARK: - 파이썬과 같은 동작

    /// 우리가 만든 명령만 식별한다(`WAYPOINT_PORT=`로 시작하고 `"<브리지>" `가 들어 있다).
    func isOurs(_ handler: OrderedJSON) -> Bool {
        guard handler["type"] == .string("command"), let command = handler["command"]?.stringValue else { return false }
        return command.hasPrefix("WAYPOINT_PORT=") && command.contains("\"" + bridgeInCommand + "\" ")
    }

    /// 우리 훅을 뺀다. 훅이 남지 않은 묶음·이벤트는 지운다(파이썬 `without_ours`).
    func withoutOurs(_ pairs: [(String, OrderedJSON)]) throws -> [(String, OrderedJSON)] {
        var result: [(String, OrderedJSON)] = []
        for (event, value) in pairs {
            guard let groups = value.arrayValue else {
                throw IntegrationInstallError.unreadable(path: hooksPath, reason: "hooks.\(event)가 배열이 아님")
            }
            var kept: [OrderedJSON] = []
            for group in groups {
                guard group.objectPairs != nil else {
                    throw IntegrationInstallError.unreadable(path: hooksPath, reason: "hooks.\(event) 묶음이 객체가 아님")
                }
                let handlers = group["hooks"]?.arrayValue ?? []
                guard handlers.allSatisfy({ $0.objectPairs != nil }) else {
                    throw IntegrationInstallError.unreadable(path: hooksPath, reason: "hooks.\(event) 훅이 객체가 아님")
                }
                let others = handlers.filter { !isOurs($0) }
                if !others.isEmpty { kept.append(group.setting("hooks", .array(others))) }
            }
            if !kept.isEmpty { result.append((event, .array(kept))) }
        }
        return result
    }

    /// `json.dumps(value, ensure_ascii=False, indent=2) + '\n'`
    static func jsonText(_ value: OrderedJSON) -> String {
        value.serialized(style: .python) + "\n"
    }

    /// 파이썬 `read_text()`: UTF-8, 줄바꿈 `\r\n`·`\r` → `\n`. 없으면 nil.
    static func readText(_ path: String) throws -> String? {
        guard let data = IntegrationFile.read(IntegrationFile.resolved(path)).data else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            throw IntegrationInstallError.unreadable(path: path, reason: "UTF-8이 아님")
        }
        return normalized(text)
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func replacingFirst(_ text: String, _ target: String, with replacement: String) -> String {
        guard let range = text.range(of: target) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }

    /// `re.sub(r'^BEGIN\n.*?^END\n?', '', text, flags=re.M | re.S)`. 줄 머리는 `\n` 뒤만 본다(파이썬과 같다).
    static func removingBlocks(_ text: String) -> String {
        let bytes = Array(text.utf8)
        let open = Array((begin + "\n").utf8)
        let close = Array(end.utf8)
        let newline = UInt8(ascii: "\n")
        func matches(_ pattern: [UInt8], at index: Int) -> Bool {
            index + pattern.count <= bytes.count && Array(bytes[index..<index + pattern.count]) == pattern
        }
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if (i == 0 || bytes[i - 1] == newline), matches(open, at: i) {
                var j = i + open.count
                var found: Int?
                while j + close.count <= bytes.count {
                    if bytes[j - 1] == newline, matches(close, at: j) { found = j; break }
                    j += 1
                }
                if let found {
                    var k = found + close.count
                    if k < bytes.count, bytes[k] == newline { k += 1 }
                    i = k
                    continue
                }
            }
            out.append(bytes[i])
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// 파이썬 `str.rstrip()`이 지우는 공백
    static func pythonRstrip(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let last = scalars.last, isPythonSpace(last) { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    static func isPythonSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: true
        default: false
        }
    }
}
