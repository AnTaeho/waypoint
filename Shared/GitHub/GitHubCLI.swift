import Foundation

/// GitHub 호출 실패. `message`는 화면과 도구 응답에 함께 쓴다.
public enum GitHubError: Error, Equatable, Sendable {
    case toolMissing
    case notLoggedIn
    case noRemote
    case notGitHub(String)
    case noBranch
    case branchNotPushed(String)
    case timedOut(Int)
    case failed(String)

    public var message: String {
        switch self {
        case .toolMissing: "이 Mac에 GitHub 도구가 없음 — 설치한 뒤 로그인"
        case .notLoggedIn: "GitHub에 로그인되어 있지 않음"
        case .noRemote: "이 프로젝트 폴더에 원격 저장소가 없음"
        case .notGitHub(let url): "원격 저장소가 GitHub 주소가 아님: \(url)"
        case .noBranch: "지금 브랜치를 알 수 없음 — 브랜치를 골라야 함"
        case .branchNotPushed(let branch): "브랜치가 원격에 없음 — 먼저 push: \(branch)"
        case .timedOut(let seconds): "\(seconds)초 안에 끝나지 않음"
        case .failed(let text): text.isEmpty ? "GitHub 요청 실패" : text
        }
    }

    /// 도구 응답에만 붙이는 해결 방법
    public var hint: String? {
        switch self {
        case .toolMissing: "gh를 설치하고 gh auth login"
        case .notLoggedIn: "터미널에서 gh auth login"
        case .noBranch: "head에 브랜치 이름을 준다"
        default: nil
        }
    }
}

/// 사용자의 `gh` 로그인으로 GitHub을 부른다. 토큰은 다루지 않는다.
public struct GitHubCLI: Sendable {
    public struct Output: Equatable, Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    /// `gh` 실행 파일. nil이면 찾지 못했다
    public var executable: String?
    public var environment: [String: String]
    public var timeout: TimeInterval
    public static let defaultTimeout: TimeInterval = 20

    public init(executable: String?, environment: [String: String], timeout: TimeInterval = GitHubCLI.defaultTimeout) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
    }

    /// 흔한 설치 폴더와 앱 PATH에서 `gh`를 찾는다. 앱은 launchd PATH로 뜨므로 그 폴더들을 PATH 앞에 붙인다.
    public static func system(home: String = NSHomeDirectory(),
                              processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> GitHubCLI {
        let path = processEnvironment["PATH"]
        let directories = ToolLaunch.searchDirectories(provider: .codex, home: home, path: path)
        let executable = directories.map { ($0 as NSString).appendingPathComponent("gh") }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        var environment = processEnvironment
        environment["HOME"] = home
        var seen = Set<String>()
        environment["PATH"] = (directories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .filter { seen.insert($0).inserted }.joined(separator: ":")
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["NO_COLOR"] = "1"
        return GitHubCLI(executable: executable, environment: environment)
    }

    /// 한 번 실행한다. `deadline`을 넘기면 멈추고 `timedOut`. 종료 코드가 0이 아니어도 출력은 돌려준다.
    public func run(_ arguments: [String], directory: String? = nil, deadline: Date? = nil) throws -> Output {
        guard let executable else { throw GitHubError.toolMissing }
        #if os(macOS)
        let limit = deadline ?? Date().addingTimeInterval(timeout)
        let folder = FileManager.default.temporaryDirectory
        let id = UUID().uuidString.prefix(8)
        let files = ["out", "err"].map { folder.appendingPathComponent("waypoint-gh-\(id).\($0)") }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }
        var handles: [FileHandle] = []
        for file in files {
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]),
                  let handle = try? FileHandle(forWritingTo: file) else { throw GitHubError.failed("출력 파일을 만들 수 없음") }
            handles.append(handle)
        }
        defer { handles.forEach { try? $0.close() } }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: directory ?? environment["HOME"] ?? NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handles[0]
        process.standardError = handles[1]
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { throw GitHubError.failed(error.localizedDescription) }
        if done.wait(timeout: .now() + max(limit.timeIntervalSinceNow, 0)) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            throw GitHubError.timedOut(Int(timeout))
        }
        let texts = files.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }
        return Output(status: process.terminationStatus, stdout: texts[0], stderr: texts[1])
        #else
        throw GitHubError.toolMissing
        #endif
    }

    /// 성공한 출력만 돌려준다. 실패는 로그인 여부를 가려 오류로 바꾼다.
    public func succeed(_ arguments: [String], directory: String? = nil, deadline: Date? = nil) throws -> Output {
        let output = try run(arguments, directory: directory, deadline: deadline)
        guard output.status == 0 else { throw Self.error(for: output) }
        return output
    }

    static func error(for output: Output) -> GitHubError {
        let text = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if output.status == 4 || lowered.contains("gh auth login") || lowered.contains("not logged in") {
            return .notLoggedIn
        }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return .failed(String(line.prefix(300)))
    }
}
