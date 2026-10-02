import Foundation

/// Claude Code 연동 계획. 대상:
/// - `~/.claude/settings.json`: `hooks.<Event>`에 Waypoint 훅(명령 경로로 식별)만 넣고 고친다. `statusLine`은 중계로 감싼다.
/// - `~/.claude/waypoint/waypoint-hook.sh`, `waypoint-statusline-tap.sh` (0755)
/// - `~/.claude/skills/tracker/SKILL.md`
/// - 사용자 범위 MCP `waypoint`(`claude mcp add/remove` 명령. `~/.claude.json`은 읽기만)
struct ClaudeInstallPlanner {
    let context: IntegrationInstallContext

    /// `integration/hooks/settings.example.json`과 같은 이벤트·차례·matcher(테스트가 비교한다).
    static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", "*"), ("SubagentStart", nil),
        ("PostToolUse", "*"), ("SubagentStop", nil), ("Stop", nil), ("SessionEnd", nil),
        ("PermissionRequest", nil), ("PostToolUseFailure", nil),
    ]
    static let hookTimeout = "2"
    static let hookPath = "~/.claude/waypoint/waypoint-hook.sh"
    static let tapPath = "~/.claude/waypoint/waypoint-statusline-tap.sh"
    static let scriptMode: UInt16 = 0o755

    var settingsPath: String { context.path(".claude/settings.json") }
    var hookScriptPath: String { context.path(".claude/waypoint/waypoint-hook.sh") }
    var tapScriptPath: String { context.path(".claude/waypoint/waypoint-statusline-tap.sh") }
    var skillPath: String { context.path(".claude/skills/tracker/SKILL.md") }
    var claudeJSONPath: String { context.path(".claude.json") }

    /// Dev는 포트·저장 폴더를 앞에 붙인다(`scripts/dev-probe-setup.sh`와 같은 꼴).
    var environmentPrefix: String {
        context.instance.isDev
            ? "WAYPOINT_PORT=\(context.port) WAYPOINT_SUPPORT_DIR=\"$HOME/Library/Application Support/\(context.instance.supportFolderName)\" "
            : ""
    }

    func command(for event: String) -> String { environmentPrefix + Self.hookPath + " " + event }

    func handler(for event: String) -> OrderedJSON {
        .object([("type", .string("command")), ("command", .string(command(for: event))),
                 ("timeout", .number(Self.hookTimeout))])
    }

    static func isOurs(_ handler: OrderedJSON) -> Bool {
        handler["type"]?.stringValue == "command"
            && handler["command"]?.stringValue?.contains("/.claude/waypoint/waypoint-hook.sh") == true
    }

    func plan(_ action: IntegrationPlan.Action) throws -> IntegrationPlan {
        var plan = IntegrationPlan(provider: .claude, action: action, files: [], commands: [], notes: [],
                                   backupFolder: IntegrationApplier.backupFolder(root: context.backupRoot, at: context.now))
        let install = action == .install
        if install {
            let hook = try context.sources.text(context.sources.hookScript)
            let tap = try context.sources.text(context.sources.statusLineTap)
            plan.set(hookScriptPath, to: Data(hook.utf8), mode: Self.scriptMode, summary: "훅 스크립트")
            plan.set(tapScriptPath, to: Data(tap.utf8), mode: Self.scriptMode, summary: "상태줄 중계")
        }
        try planSettings(install: install, into: &plan)
        try planSkill(install: install, into: &plan)
        planMCP(install: install, into: &plan)
        return plan
    }

    // MARK: - settings.json

    private func planSettings(install: Bool, into plan: inout IntegrationPlan) throws {
        let disk = IntegrationFile.read(IntegrationFile.resolved(settingsPath))
        let text = disk.data.flatMap { String(data: $0, encoding: .utf8) }
        if disk.data != nil && text == nil {
            throw IntegrationInstallError.unreadable(path: settingsPath, reason: "UTF-8이 아님")
        }
        let isBlank = text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let root: OrderedJSON
        do {
            root = isBlank ? .object([]) : try OrderedJSON.parse(text ?? "")
        } catch {
            throw IntegrationInstallError.unreadable(path: settingsPath, reason: "JSON이 아님")
        }
        guard root.objectPairs != nil else {
            throw IntegrationInstallError.unreadable(path: settingsPath, reason: "최상위가 객체가 아님")
        }
        var updated = root
        let hooks = root["hooks"] ?? .object([])
        guard let hookPairs = hooks.objectPairs else {
            throw IntegrationInstallError.unreadable(path: settingsPath, reason: "hooks가 객체가 아님")
        }
        let newHooks = try mergeHooks(hookPairs, install: install)
        if newHooks.isEmpty && root["hooks"] != nil && !install && !hookPairs.isEmpty {
            updated = updated.setting("hooks", nil)
        } else if !newHooks.isEmpty || root["hooks"] != nil {
            updated = updated.setting("hooks", .object(newHooks))
        }
        updated = planStatusLine(updated, install: install, notes: &plan.notes)
        guard updated != root else { return }
        let output = Self.serialize(updated, like: text)
        plan.set(settingsPath, to: Data(output.utf8), mode: nil, newMode: 0o644,
                 summary: install ? "훅·상태줄 연결" : "훅·상태줄 연결 해제")
    }

    /// 이벤트마다 Waypoint 훅을 맞춘다. 이미 맞는 이벤트는 그대로 두고, 다른 사용자 훅의 차례는 지킨다.
    func mergeHooks(_ pairs: [(String, OrderedJSON)], install: Bool) throws -> [(String, OrderedJSON)] {
        let wanted = install ? Dictionary(uniqueKeysWithValues: Self.events.map { ($0.name, $0.matcher) }) : [:]
        var result: [(String, OrderedJSON)] = []
        for (event, value) in pairs {
            guard let groups = value.arrayValue else {
                throw IntegrationInstallError.unreadable(path: settingsPath, reason: "hooks.\(event)가 배열이 아님")
            }
            if let matcher = wanted[event], satisfied(groups, event: event, matcher: matcher) {
                result.append((event, value))
                continue
            }
            var kept: [OrderedJSON] = []
            var insertAt: Int?
            for group in groups {
                guard let handlers = group["hooks"]?.arrayValue, handlers.contains(where: Self.isOurs) else {
                    kept.append(group)
                    continue
                }
                if insertAt == nil { insertAt = kept.count }
                let others = handlers.filter { !Self.isOurs($0) }
                if !others.isEmpty { kept.append(group.setting("hooks", .array(others))) }
            }
            if let matcher = wanted[event] {
                kept.insert(desiredGroup(event: event, matcher: matcher), at: min(insertAt ?? kept.count, kept.count))
            }
            // Waypoint 훅만 있던 이벤트는 빈 배열로 남기지 않는다
            if kept.isEmpty && insertAt != nil { continue }
            result.append((event, .array(kept)))
        }
        for (event, matcher) in Self.events where install && !pairs.contains(where: { $0.0 == event }) {
            result.append((event, .array([desiredGroup(event: event, matcher: matcher)])))
        }
        return result
    }

    private func desiredGroup(event: String, matcher: String?) -> OrderedJSON {
        var pairs: [(String, OrderedJSON)] = []
        if let matcher { pairs.append(("matcher", .string(matcher))) }
        pairs.append(("hooks", .array([handler(for: event)])))
        return .object(pairs)
    }

    /// Waypoint 훅이 정확히 하나, 바라는 명령·제한 시간이고, 그 묶음의 matcher가 같은 뜻(없음·""·"*"은 모든 도구)인가.
    private func satisfied(_ groups: [OrderedJSON], event: String, matcher: String?) -> Bool {
        var found: [(group: OrderedJSON, handler: OrderedJSON)] = []
        for group in groups {
            for handler in group["hooks"]?.arrayValue ?? [] where Self.isOurs(handler) {
                found.append((group, handler))
            }
        }
        guard found.count == 1, let only = found.first else { return false }
        let wantedKeys = Set(["type", "command", "timeout"])
        guard let handlerPairs = only.handler.objectPairs, Set(handlerPairs.map(\.0)) == wantedKeys,
              only.handler["command"] == .string(command(for: event)),
              only.handler["timeout"] == .number(Self.hookTimeout) else { return false }
        let current = only.group["matcher"]
        if current == nil || current == .string("") || current == .string("*") {
            return matcher == nil || matcher == "*"
        }
        return current == matcher.map(OrderedJSON.string)
    }

    // MARK: - statusLine

    var tapPrefix: String {
        (context.instance.isDev
            ? "WAYPOINT_SUPPORT_DIR=\"$HOME/Library/Application Support/\(context.instance.supportFolderName)\" " : "")
            + "bash " + Self.tapPath
    }

    private func planStatusLine(_ root: OrderedJSON, install: Bool, notes: inout [IntegrationPlan.Note]) -> OrderedJSON {
        let status = root["statusLine"]
        guard let status else {
            // 상태줄이 없으면 중계만 둔다(출력 없음). 사용량 게이지가 이 입력을 쓴다.
            return install ? root.setting("statusLine", .object([("type", .string("command")), ("command", .string(tapPrefix))]))
                : root
        }
        guard status.objectPairs != nil, status["type"]?.stringValue ?? "command" == "command",
              let command = status["command"]?.stringValue else {
            notes.append(.init(step: "상태줄", reason: "명령 상태줄이 아님"))
            return root
        }
        switch StatusLineWrap.unwrap(command, home: context.commandHome) {
        case .notWrapped:
            guard install else { return root }
            return root.setting("statusLine", status.setting("command", .string(StatusLineWrap.wrap(command, prefix: tapPrefix))))
        case .wrapped(let original):
            if install {
                let wanted = original.map { StatusLineWrap.wrap($0, prefix: tapPrefix) } ?? tapPrefix
                return wanted == command ? root : root.setting("statusLine", status.setting("command", .string(wanted)))
            }
            guard let original else { return root.setting("statusLine", nil) }
            return root.setting("statusLine", status.setting("command", .string(original)))
        case .unrecognized:
            notes.append(.init(step: "상태줄", reason: "직접 고친 중계 명령"))
            return root
        }
    }

    // MARK: - 스킬

    private func planSkill(install: Bool, into plan: inout IntegrationPlan) throws {
        let disk = IntegrationFile.read(IntegrationFile.resolved(skillPath))
        let current = disk.data.flatMap { String(data: $0, encoding: .utf8) }
        let ours = current.map(Self.isWaypointTrackerSkill) ?? true
        if install {
            let skill = try context.sources.text(context.sources.trackerSkill)
            guard ours else {
                plan.notes.append(.init(step: "tracker 스킬", reason: "같은 이름의 다른 스킬이 있음"))
                return
            }
            plan.set(skillPath, to: Data(skill.utf8), mode: nil, newMode: 0o644, summary: "tracker 스킬")
        } else if disk.data != nil {
            guard ours else {
                plan.notes.append(.init(step: "tracker 스킬", reason: "같은 이름의 다른 스킬이 있음"))
                return
            }
            plan.set(skillPath, to: nil, mode: nil, summary: "tracker 스킬 지움")
        }
    }

    /// 머리말 `name: tracker`이고 Waypoint를 말하는 스킬(옛 판 포함)
    static func isWaypointTrackerSkill(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).prefix(10)
            .contains { $0.trimmingCharacters(in: .whitespaces) == "name: tracker" } && text.contains("Waypoint")
    }

    // MARK: - MCP

    /// `~/.claude.json`의 사용자 범위 `mcpServers.waypoint`(읽기만)
    func registeredMCP() -> (exists: Bool, type: String?, url: String?) {
        guard let data = FileManager.default.contents(atPath: claudeJSONPath),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any], let server = servers["waypoint"] else {
            return (false, nil, nil)
        }
        let dict = server as? [String: Any]
        return (true, dict?["type"] as? String, dict?["url"] as? String)
    }

    /// Waypoint 앱이 여는 주소 꼴(포트만 다를 수 있다)
    static func isWaypointURL(_ url: String?) -> Bool {
        url?.range(of: #"^http://(127\.0\.0\.1|localhost):[0-9]+/mcp$"#, options: .regularExpression) != nil
    }

    private func planMCP(install: Bool, into plan: inout IntegrationPlan) {
        let current = registeredMCP()
        if install {
            if !current.exists {
                plan.commands = [.claudeMCPAdd(url: context.mcpURL)]
            } else if current.url == context.mcpURL && (current.type ?? "http") == "http" {
                return
            } else if Self.isWaypointURL(current.url) {
                plan.commands = [.claudeMCPRemove, .claudeMCPAdd(url: context.mcpURL)]
            } else {
                plan.notes.append(.init(step: "MCP 등록", reason: "다른 waypoint MCP 서버가 있음"))
            }
        } else if current.exists {
            if Self.isWaypointURL(current.url) {
                plan.commands = [.claudeMCPRemove]
            } else {
                plan.notes.append(.init(step: "MCP 해제", reason: "다른 waypoint MCP 서버가 있음"))
            }
        }
    }

    // MARK: - 쓰기 꼴

    /// 원문의 들여쓰기(둘째 줄 앞 공백)와 끝 줄바꿈을 따른다. 원문이 없으면 2칸·끝 줄바꿈.
    static func serialize(_ value: OrderedJSON, like original: String?) -> String {
        var indent = "  "
        var trailingNewline = true
        if let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = original.split(separator: "\n", omittingEmptySubsequences: true)
            if lines.count > 1 {
                let lead = lines[1].prefix { $0 == " " || $0 == "\t" }
                if !lead.isEmpty { indent = String(lead) }
            }
            trailingNewline = original.hasSuffix("\n")
        }
        return value.serialized(style: .init(indent: indent)) + (trailingNewline ? "\n" : "")
    }
}

/// 상태줄 명령을 Waypoint 중계로 감싸고 푼다. 감싼 명령에서 원래 명령을 그대로 되찾을 수 있어야 한다(따로 적어 두지 않는다).
enum StatusLineWrap {
    enum Unwrapped: Equatable {
        case notWrapped
        /// 중계로 감쌌다. 원래 명령(없으면 nil)
        case wrapped(String?)
        /// 중계가 들어 있지만 이 꼴이 아니다(사용자가 고침)
        case unrecognized
    }

    /// 낱말로 나눠도 뜻이 같은 명령: 셸 특수 문자가 없고 첫 낱말이 변수 지정이 아니다.
    static func isPlain(_ command: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./~@%+=:,- ")
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty,
              command.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        let first = command.split(separator: " ").first ?? ""
        return !first.contains("=") && !command.hasPrefix(" ")
    }

    static func wrap(_ original: String, prefix: String) -> String {
        prefix + " " + (isPlain(original) ? original : "bash -c " + ToolLaunch.quote(original))
    }

    static func unwrap(_ command: String, home: String) -> Unwrapped {
        guard command.contains("waypoint-statusline-tap.sh") else { return .notWrapped }
        var rest = Substring(command)
        if rest.hasPrefix("WAYPOINT_SUPPORT_DIR=\"") {
            let afterQuote = rest.dropFirst("WAYPOINT_SUPPORT_DIR=\"".count)
            guard let close = afterQuote.firstIndex(of: "\""),
                  afterQuote[afterQuote.index(after: close)...].hasPrefix(" ") else { return .unrecognized }
            rest = afterQuote[afterQuote.index(close, offsetBy: 2)...]
        }
        let scripts = ["~", "$HOME", home].map { "bash \($0)/.claude/waypoint/waypoint-statusline-tap.sh" }
        guard let script = scripts.first(where: { rest.hasPrefix($0) }) else { return .unrecognized }
        rest = rest.dropFirst(script.count)
        if rest.isEmpty { return .wrapped(nil) }
        guard rest.hasPrefix(" ") else { return .unrecognized }
        let original = String(rest.dropFirst())
        if original.hasPrefix("bash -c '"), let inner = unquote(String(original.dropFirst("bash -c ".count))) {
            return .wrapped(inner)
        }
        return .wrapped(original)
    }

    /// `ToolLaunch.quote`의 역. 그 꼴이 아니면 nil
    static func unquote(_ token: String) -> String? {
        guard token.count >= 2, token.hasPrefix("'"), token.hasSuffix("'") else { return nil }
        let value = String(token.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        return ToolLaunch.quote(value) == token ? value : nil
    }
}
