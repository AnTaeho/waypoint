import Foundation
import Testing
@testable import WaypointKit

/// Codex 연동 설치기. `scripts/install-codex.py`를 옮긴 것이라 같은 입력에서 파이썬과 같은 바이트를 쓰는지 비교한다
/// (Codex는 훅을 해시로 신뢰하므로 같은 `hooks.json`이어야 다시 설치해도 신뢰가 풀리지 않는다).
@Suite struct CodexInstallerTests {

    /// `tomllib`가 있는 python3(3.11+). 없으면 비교 테스트를 건너뛴다.
    static let python: String? = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { path in
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "import tomllib"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static let userConfig = "model = \"test-model\"\n[mcp_servers.other]\nurl = \"http://localhost:9999\"\n"
    static let userHooks = #"{"description": "keep", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo other"}]}]}}"#

    /// 파이썬 백업 폴더와 install.json의 백업 경로는 두 구현이 다르다(자리만 다름). 나머지는 바이트·권한까지 같아야 한다.
    private func normalized(_ snapshot: [String: InstallSandbox.Entry]) -> [String: InstallSandbox.Entry] {
        var result = snapshot.filter { $0.value.data != nil } // 폴더는 비교하지 않는다(파이썬은 백업 폴더를 만든다)
        if var manifest = result[".codex/waypoint/install.json"], let data = manifest.data,
           let text = String(data: data, encoding: .utf8) {
            let replaced = text.replacingOccurrences(of: #""backup": "[^"]*""#, with: #""backup": "-""#, options: .regularExpression)
            manifest.data = Data(replaced.utf8)
            result[".codex/waypoint/install.json"] = manifest
        }
        return result
    }

    private func runPython(_ box: InstallSandbox, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(Self.python))
        process.arguments = [InstallSandbox.repository.appendingPathComponent("scripts/install-codex.py").path,
                             "--home", box.home.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// 같은 시작 상태에서 파이썬과 Swift를 차례로 돌려 결과를 비교하고, 파이썬 결과를 돌려준다(다음 단계의 시작).
    @discardableResult
    private func compare(_ box: InstallSandbox, from start: [String: InstallSandbox.Entry],
                         dev: Bool = false, remove: Bool = false,
                         sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: InstallSandbox.Entry] {
        let excluded = [".codex/waypoint/backups"]
        box.restore(start)
        var arguments: [String] = []
        if dev { arguments.append("--dev") }
        if remove { arguments.append("--remove") }
        let status = try runPython(box, arguments)
        let python = box.snapshot(excluding: excluded)

        box.restore(start)
        var swiftError: Error?
        do {
            try box.run(.codex, remove ? .remove : .install, dev ? .dev : .stable)
        } catch {
            swiftError = error
        }
        let swift = box.snapshot(excluding: excluded)
        #expect((status == 0) == (swiftError == nil), "python \(status), swift \(String(describing: swiftError))",
                sourceLocation: sourceLocation)
        let p = normalized(python), s = normalized(swift)
        #expect(p.keys.sorted() == s.keys.sorted(), sourceLocation: sourceLocation)
        for key in p.keys.sorted() where p[key] != s[key] {
            Issue.record("다름: \(key)\npython: \(p[key].map(String.init(describing:)) ?? "-")\nswift: \(s[key].map(String.init(describing:)) ?? "-")",
                         sourceLocation: sourceLocation)
        }
        box.restore(python)
        return python
    }

    @Test(.enabled(if: python != nil, "tomllib가 있는 python3 없음"))
    func matchesPythonInstallerByteForByte() throws {
        let box = InstallSandbox()
        // 사용자 설정이 있는 홈: 설치 → 다시 설치 → Dev → 평소용 → 해제 → 다시 해제
        box.write(".codex/config.toml", Self.userConfig)
        box.write(".codex/hooks.json", Self.userHooks)
        var state = box.snapshot()
        for step in [(false, false), (false, false), (true, false), (false, false), (false, true), (false, true)] {
            state = try compare(box, from: state, dev: step.0, remove: step.1)
        }
        // 빈 홈: 설치 → 해제
        let empty = InstallSandbox()
        state = try compare(empty, from: empty.snapshot())
        try compare(empty, from: state, remove: true)
    }

    @Test(.enabled(if: python != nil, "tomllib가 있는 python3 없음"))
    func matchesPythonOnEdgeInputs() throws {
        let cases: [(String, String?, String?)] = [
            ("이미 같은 MCP", "[mcp_servers.waypoint]\nurl = \"http://127.0.0.1:47821/mcp\"\n", nil),
            ("다른 MCP(멈춤)", "[mcp_servers.waypoint]\nurl = \"https://example.com/private\"\n", nil),
            ("훅 꺼짐(멈춤)", "[features]\nhooks = false\n", nil),
            ("TOML 아님(멈춤)", "not valid TOML", nil),
            ("CRLF·끝 공백", "model = \"x\"\r\n\r\n  \n", "{\r\n  \"hooks\": {}\r\n}"),
            ("빈 hooks.json", nil, ""),
            ("묶음 안에 다른 훅과 함께", nil,
             #"{"hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "echo a"}], "x": 1.50}], "Empty": []}}"#),
            ("유니코드·이스케이프", "# 한글 주석\nname = '리터럴'\n", #"{"note": "é é \n \/  ", "n": -0, "f": 1E3}"#),
        ]
        for (name, config, hooks) in cases {
            let box = InstallSandbox()
            if let config { box.write(".codex/config.toml", config) }
            if let hooks { box.write(".codex/hooks.json", hooks) }
            let start = box.snapshot()
            let installed = try compare(box, from: start)
            try compare(box, from: installed, remove: true)
            _ = name
        }
    }

    @Test(.enabled(if: python != nil, "tomllib가 있는 python3 없음"))
    func matchesPythonWhenSkillWasEdited() throws {
        let box = InstallSandbox()
        let installed = try compare(box, from: box.snapshot())
        box.restore(installed)
        box.write(".agents/skills/waypoint-tracker/SKILL.md", (box.text(".agents/skills/waypoint-tracker/SKILL.md") ?? "") + "\n사용자 메모\n", mode: 0o600)
        let edited = box.snapshot()
        try compare(box, from: edited) // 둘 다 멈춤
        try compare(box, from: edited, remove: true) // 고친 스킬은 남긴다
    }

    @Test func reinstallWritesNothingAndKeepsTrustHash() throws {
        let box = InstallSandbox()
        box.write(".codex/config.toml", Self.userConfig)
        box.write(".codex/hooks.json", Self.userHooks)
        try box.run(.codex, .install)
        let after = box.snapshot()
        let plan = try IntegrationInstaller.plan(.codex, .install, context: box.context())
        #expect(plan.isEmpty, "\(plan.files.map(\.summary))")
        try box.run(.codex, .install)
        #expect(box.snapshot() == after)
        #expect(box.mode(".codex/waypoint/waypoint-codex-hook.sh") == 0o700)
        #expect(box.mode(".codex/waypoint/waypoint-hook.sh") == 0o700)
    }

    @Test func conflictsStopBeforeWriting() throws {
        for config in ["[mcp_servers.waypoint]\nurl = \"https://example.com/private\"\n", "[features]\nhooks = false\n",
                       "features.hooks = false\n", "not valid TOML", "a = \"unterminated\n", "[x]\na = 1\na = 2\n"] {
            let box = InstallSandbox()
            box.write(".codex/config.toml", config)
            let before = box.snapshot()
            #expect(throws: IntegrationInstallError.self, "\(config)") {
                try IntegrationInstaller.plan(.codex, .install, context: box.context())
            }
            #expect(box.snapshot() == before)
        }
    }

    @Test func secondWriteFailureRollsBack() throws {
        let box = InstallSandbox()
        box.write(".codex/config.toml", Self.userConfig, mode: 0o600)
        box.write(".codex/hooks.json", Self.userHooks, mode: 0o600)
        let before = box.snapshot()
        let plan = try IntegrationInstaller.plan(.codex, .install, context: box.context())
        let calls = Counter()
        let failing = IntegrationApplier { path, data, mode in
            if calls.next() == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try IntegrationFile.apply(path: path, data: data, mode: mode)
        }
        #expect(throws: IntegrationInstallError.self) {
            try IntegrationInstaller.apply(plan, context: box.context(), applier: failing)
        }
        #expect(box.snapshot() == before)
    }

    @Test func homeWithShellCharactersIsRefused() {
        let box = InstallSandbox()
        let context = IntegrationInstallContext(home: box.home, commandHome: "/Users/a$b", instance: .stable,
                                                sources: InstallSandbox.sources, backupRoot: box.backups)
        #expect(throws: IntegrationInstallError.self) {
            try IntegrationInstaller.plan(.codex, .install, context: context)
        }
    }

    @Test func blockRemovalMatchesPythonRegex() {
        let begin = CodexInstallPlanner.begin, end = CodexInstallPlanner.end
        let block = "\(begin)\n[mcp_servers.waypoint]\nurl = \"u\"\n\(end)\n"
        #expect(CodexInstallPlanner.removingBlocks("a = 1\n\n" + block) == "a = 1\n\n")
        #expect(CodexInstallPlanner.removingBlocks("x" + block) == "x" + block) // 줄 머리가 아니면 그대로
        #expect(CodexInstallPlanner.removingBlocks(block + "b = 2\n" + block) == "b = 2\n")
        #expect(CodexInstallPlanner.removingBlocks("\(begin)\nno end\n") == "\(begin)\nno end\n")
        #expect(CodexInstallPlanner.removingBlocks("\(begin)\n\(end)") == "")
        #expect(CodexInstallPlanner.pythonRstrip("a \n\t\u{3000}") == "a")
    }

    @Test func miniTOMLReadsWhatInstallerNeeds() throws {
        let toml = try MiniTOML("""
        model = "m" # 주석
        notify = ["/a b", "--x", "[\\"q\\"]"]
        multi = \"\"\"
        여러 줄 \"\" 따옴표\"\"\"
        lit = '''x'''
        date = 1979-05-27 07:32:00Z
        [features]
        js_repl = false
        [mcp_servers.node_repl.env]
        A = "1"
        [mcp_servers."quoted key"]
        url = "x"
        [projects."/Users/me/폴더"]
        trust_level = "trusted"
        [[arr]]
        k = 1
        [[arr]]
        k = 2
        [tui.model_availability_nux]
        "gpt-5.6-sol" = 4
        gpt-6-astra = 4
        inline = { url = "http://x", n = [1, 2] }
        """)
        #expect(toml.leaf(["features", "js_repl"]) == .other("false"))
        #expect(toml.leaf(["multi"]) == .string("여러 줄 \"\" 따옴표"))
        #expect(toml.leaf(["mcp_servers", "quoted key", "url"]) == .string("x"))
        #expect(!toml.contains(["mcp_servers", "waypoint"]))
        #expect(toml.contains(["mcp_servers", "node_repl"]))
        #expect(toml.flatTable(["mcp_servers", "node_repl"]) == nil) // 하위 표가 있다
        #expect(toml.leaf(["tui", "model_availability_nux", "inline", "url"]) == .string("http://x"))

        let dotted = try MiniTOML("[mcp_servers]\nwaypoint.url = \"u\"\n")
        #expect(dotted.flatTable(["mcp_servers", "waypoint"]) == ["url": .string("u")])
        let inline = try MiniTOML("mcp_servers.waypoint = { url = \"u\" }\n")
        #expect(inline.flatTable(["mcp_servers", "waypoint"]) == ["url": .string("u")])
        let empty = try MiniTOML("[mcp_servers.waypoint]\n")
        #expect(empty.contains(["mcp_servers", "waypoint"]) && empty.flatTable(["mcp_servers", "waypoint"]) == [:])
        #expect(throws: MiniTOML.ParseError.self) { try MiniTOML("[a]\n[a]\n") }
        #expect(throws: MiniTOML.ParseError.self) { try MiniTOML("a = [1, 2\n") }
        #expect(throws: MiniTOML.ParseError.self) { try MiniTOML("a = 1 b = 2\n") }
    }
}
