import Foundation

public enum GitHubKind: String, Codable, Sendable, CaseIterable {
    case issue, pr

    public var name: String { self == .issue ? "이슈" : "PR" }
    public var eventType: EventType { self == .issue ? .githubIssue : .githubPR }
}

public enum GitHubState: String, Codable, Sendable, CaseIterable {
    case open, closed, merged, draft

    public var label: String {
        switch self {
        case .open: "열림"
        case .closed: "닫힘"
        case .merged: "병합됨"
        case .draft: "초안"
        }
    }

    /// 아직 끝나지 않았다(열린 수에 센다)
    public var isOpen: Bool { self == .open || self == .draft }
}

/// 열려는 이슈·PR의 내용(도구 인자·시트 입력).
public struct GitHubDraft: Equatable, Sendable {
    public var kind: GitHubKind
    public var title: String
    public var body: String
    public var labels: [String]
    public var base: String?
    public var head: String?
    public var isDraft: Bool

    public init(kind: GitHubKind, title: String, body: String = "", labels: [String] = [], base: String? = nil,
                head: String? = nil, isDraft: Bool = false) {
        self.kind = kind
        self.title = title
        self.body = body
        self.labels = labels
        self.base = base
        self.head = head
        self.isDraft = isDraft
    }
}

/// 만들어진 이슈·PR.
public struct GitHubCreated: Equatable, Sendable {
    public let kind: GitHubKind
    public let repo: String
    public let number: Int
    public let url: String
    public let title: String
    public let state: GitHubState
    public let branch: String?
}

/// 저장소·브랜치가 정해진 호출 하나. 백그라운드에서 `run`한다.
public struct GitHubJob: Equatable, Sendable {
    public let draft: GitHubDraft
    /// `owner/name`
    public let repo: String
    /// 실행 폴더(작업 트리)
    public let directory: String

    public var arguments: [String] {
        var args = [draft.kind.rawValue, "create", "--repo", repo, "--title", draft.title, "--body", draft.body]
        switch draft.kind {
        case .issue:
            for label in draft.labels { args += ["--label", label] }
        case .pr:
            if let head = draft.head { args += ["--head", head] }
            if let base = draft.base { args += ["--base", base] }
            if draft.isDraft { args.append("--draft") }
        }
        return args
    }

    public func run(_ cli: GitHubCLI) -> Result<GitHubCreated, GitHubError> {
        do {
            let output = try cli.succeed(arguments, directory: directory, deadline: Date().addingTimeInterval(cli.timeout))
            guard let created = Self.created(from: output.stdout, job: self) else {
                return .failure(.failed("만든 주소를 읽지 못함"))
            }
            return .success(created)
        } catch let error as GitHubError {
            return .failure(Self.refine(error, head: draft.head))
        } catch {
            return .failure(.failed(String(describing: error)))
        }
    }

    /// 출력의 마지막 주소 줄에서 번호를 읽는다(`https://github.com/o/r/issues/12`).
    static func created(from stdout: String, job: GitHubJob) -> GitHubCreated? {
        let lines = stdout.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let url = lines.last(where: { $0.hasPrefix("https://") }),
              let number = Int(url.split(separator: "/").last ?? "") else { return nil }
        let draft = job.draft
        return GitHubCreated(kind: draft.kind, repo: job.repo, number: number, url: url, title: draft.title,
                             state: draft.kind == .pr && draft.isDraft ? .draft : .open,
                             branch: draft.kind == .pr ? draft.head : nil)
    }

    /// 원격에 브랜치가 없어서 난 실패를 알아볼 수 있는 오류로 바꾼다.
    static func refine(_ error: GitHubError, head: String?) -> GitHubError {
        guard case .failed(let text) = error, let head else { return error }
        let lowered = text.lowercased()
        let missing = ["head sha can't be blank", "head ref must be a branch"]
        return missing.contains(where: lowered.contains)
            ? .branchNotPushed(head) : error
    }
}

/// 프로젝트 폴더의 `origin`이 가리키는 GitHub 저장소.
public struct GitHubRepo: Equatable, Sendable {
    /// `owner/name`
    public let name: String
    /// 작업 트리 최상위
    public let checkout: String

    static let host = "github.com/"

    public static func read(rootPath: String, home: String = NSHomeDirectory(),
                            fileManager: FileManager = .default) throws -> GitHubRepo {
        let root = ProjectMatcher.normalize(rootPath, home: home)
        let probe = (root as NSString).appendingPathComponent(".waypoint-probe")
        guard root.hasPrefix("/"), let checkout = GitInfo.checkoutRoot(for: probe, fileManager: fileManager),
              let common = GitInfo.commonDirectory(checkout: checkout, fileManager: fileManager),
              let config = try? String(contentsOfFile: (common as NSString).appendingPathComponent("config"), encoding: .utf8),
              let origin = LocalOrigin.originURL(config: config)
        else { throw GitHubError.noRemote }
        guard let name = name(origin: origin) else { throw GitHubError.notGitHub(origin) }
        return GitHubRepo(name: name, checkout: checkout)
    }

    /// 원격 주소 → `owner/name`(대소문자는 원문대로). GitHub 주소가 아니면 nil.
    public static func name(origin: String) -> String? {
        guard let normalized = GitRemoteURL.normalize(origin), normalized.hasPrefix(host) else { return nil }
        let path = normalized.dropFirst(host.count)
        guard path.split(separator: "/").count == 2 else { return nil }
        var raw = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if raw.hasSuffix(".git") { raw.removeLast(4) }
        while raw.hasSuffix("/") { raw.removeLast() }
        let tail = String(raw.suffix(path.count))
        return tail.lowercased() == path ? tail : String(path)
    }
}

/// 입력을 확인해 호출 하나로 만든다(앱 시트와 도구가 함께 쓴다). 네트워크를 쓰지 않는다.
public enum GitHubPlanner {
    /// - cwd: PR의 브랜치를 읽을 작업 트리. 없으면 프로젝트 폴더
    public static func job(_ input: GitHubDraft, rootPath: String, cwd: String? = nil,
                           home: String = NSHomeDirectory()) throws -> GitHubJob {
        var draft = input
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { throw GitHubError.failed("제목이 비어 있음") }
        draft.labels = draft.labels.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft.base = clean(draft.base)
        draft.head = clean(draft.head)
        let repo = try GitHubRepo.read(rootPath: rootPath, home: home)
        guard draft.kind == .pr else {
            draft.base = nil; draft.head = nil; draft.isDraft = false
            return GitHubJob(draft: draft, repo: repo.name, directory: repo.checkout)
        }
        draft.labels = []
        let directory = clean(cwd).map { ProjectMatcher.normalize($0, home: home) } ?? repo.checkout
        guard let head = draft.head ?? GitInfo.branch(at: directory) else { throw GitHubError.noBranch }
        draft.head = head
        // 다른 사람 저장소의 브랜치(`owner:branch`)는 이 작업 트리로 알 수 없다
        if !head.contains(":") {
            guard let refs = GitRefs.read(directory: directory), refs.remote.contains(head) else {
                throw GitHubError.branchNotPushed(head)
            }
        }
        return GitHubJob(draft: draft, repo: repo.name, directory: directory)
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
