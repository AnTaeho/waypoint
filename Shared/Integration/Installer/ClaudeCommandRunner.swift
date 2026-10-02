import Foundation

/// Claude Code CLI로 MCP 서버를 등록·해제한다. `~/.claude.json`은 Claude Code가 자주 쓰는 큰 파일이라 직접 고치지 않는다.
public struct ClaudeCommandRunner: Sendable {
    /// `claude` 실행 파일. nil이면 찾지 못했다
    public var executable: String?
    public var environment: [String: String]
    public var timeout: TimeInterval

    public init(executable: String?, environment: [String: String], timeout: TimeInterval = 20) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
    }

    public static func arguments(for command: IntegrationPlan.Command) -> [String] {
        switch command {
        case .claudeMCPAdd(let url): ["mcp", "add", "--transport", "http", "--scope", "user", "waypoint", url]
        case .claudeMCPRemove: ["mcp", "remove", "waypoint", "-s", "user"]
        }
    }

    /// 흔한 설치 폴더와 앱 PATH에서 `claude`를 찾는다(`ToolLaunch`). 앱은 launchd PATH로 뜨므로 실행 파일 폴더와
    /// 흔한 폴더를 PATH 앞에 붙인다(npm으로 설치한 `claude`는 `node`를 PATH에서 찾는다).
    public static func system(home: String, processEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> ClaudeCommandRunner {
        let path = processEnvironment["PATH"]
        let executable = ToolLaunch.executable(provider: .claude, home: home, path: path,
                                               isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        var environment = processEnvironment
        environment["HOME"] = home
        var dirs = executable.map { [($0 as NSString).deletingLastPathComponent] } ?? []
        dirs += ToolLaunch.searchDirectories(provider: .claude, home: home, path: path)
        var seen = Set<String>()
        environment["PATH"] = (dirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return ClaudeCommandRunner(executable: executable, environment: environment)
    }

    public func run(_ command: IntegrationPlan.Command) -> IntegrationInstaller.StepOutcome {
        guard let executable else { return .executableMissing }
        #if os(macOS)
        return Self.launch(executable, arguments: Self.arguments(for: command), environment: environment, timeout: timeout)
        #else
        return .executableMissing
        #endif
    }

    #if os(macOS)
    private static func launch(_ executable: String, arguments: [String], environment: [String: String],
                               timeout: TimeInterval) -> IntegrationInstaller.StepOutcome {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint-claude-\(UUID().uuidString.prefix(8)).log")
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: output) else { return .failed("출력 파일을 만들 수 없음") }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return .failed(error.localizedDescription)
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            return .failed("\(Int(timeout))초 안에 끝나지 않음")
        }
        guard process.terminationStatus == 0 else {
            let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
            let line = text.split(separator: "\n").last.map(String.init) ?? ""
            return .failed("종료 코드 \(process.terminationStatus)" + (line.isEmpty ? "" : ": " + String(line.prefix(200))))
        }
        return .done
    }
    #endif
}
