#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 가짜 `gh`: 받은 인자를 파일에 적고 정해 둔 출력·종료 코드를 낸다. 네트워크를 쓰지 않는다.
struct FakeGH {
    let folder: URL

    init(stdout: String = "", stderr: String = "", status: Int = 0, sleep: Double = 0) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-fakegh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try stdout.write(to: folder.appendingPathComponent("stdout"), atomically: true, encoding: .utf8)
        try stderr.write(to: folder.appendingPathComponent("stderr"), atomically: true, encoding: .utf8)
        let script = """
        #!/bin/sh
        DIR=$(dirname "$0")
        for arg in "$@"; do printf '%s\\037' "$arg" >> "$DIR/args"; done
        printf '\\036' >> "$DIR/args"
        sleep \(sleep)
        cat "$DIR/stdout"
        cat "$DIR/stderr" >&2
        exit \(status)

        """
        let url = folder.appendingPathComponent("gh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func cli(timeout: TimeInterval = 10) -> GitHubCLI {
        GitHubCLI(executable: folder.appendingPathComponent("gh").path,
                  environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path], timeout: timeout)
    }

    /// 호출마다 받은 인자
    var calls: [[String]] {
        let text = (try? String(contentsOf: folder.appendingPathComponent("args"), encoding: .utf8)) ?? ""
        return text.split(separator: "\u{1E}").map { $0.split(separator: "\u{1F}", omittingEmptySubsequences: false).dropLast().map(String.init) }
    }
}

/// `.git`만 흉내 낸 작업 트리(`origin`·현재 브랜치·원격에 있는 브랜치).
func makeCheckout(origin: String? = "git@github.com:Me/App.git", branch: String = "feat/x",
                  pushed: [String] = ["main", "feat/x"], local: [String] = ["main", "feat/x", "wip"]) throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-repo-\(UUID().uuidString)")
    let git = root.appendingPathComponent(".git")
    func write(_ path: String, _ text: String) throws {
        let url = git.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    try write("HEAD", "ref: refs/heads/\(branch)\n")
    try write("config", origin.map { "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = \($0)\n" } ?? "[core]\n")
    for name in local { try write("refs/heads/\(name)", "0000\n") }
    // 하나는 packed-refs로만
    for name in pushed.dropFirst() { try write("refs/remotes/origin/\(name)", "0000\n") }
    if let first = pushed.first {
        try write("packed-refs", "# pack-refs with: peeled\n0000 refs/remotes/origin/\(first)\n")
        try write("refs/remotes/origin/HEAD", "ref: refs/remotes/origin/\(first)\n")
    }
    return (root.path as NSString).resolvingSymlinksInPath
}

@Suite struct GitHubJobTests {
    @Test func repoNameKeepsCaseAndRejectsOtherHosts() {
        #expect(GitHubRepo.name(origin: "git@github.com:Me/App.git") == "Me/App")
        #expect(GitHubRepo.name(origin: "https://github.com/Me/App/") == "Me/App")
        #expect(GitHubRepo.name(origin: "ssh://git@github.com/me/app") == "me/app")
        #expect(GitHubRepo.name(origin: "git@gitlab.com:me/app.git") == nil)
        #expect(GitHubRepo.name(origin: "https://github.com/me") == nil)
        #expect(GitHubRepo.name(origin: "/srv/app.git") == nil)
    }

    @Test func refsListLocalAndPushedBranches() throws {
        let refs = try #require(GitRefs.read(directory: try makeCheckout()))
        #expect(refs.local == ["feat/x", "main", "wip"])
        #expect(refs.remote == ["main", "feat/x"])
        #expect(refs.pushed == ["feat/x", "main"])
        #expect(refs.defaultBranch == "main")
    }

    @Test func issueArguments() throws {
        let root = try makeCheckout()
        let job = try GitHubPlanner.job(
            GitHubDraft(kind: .issue, title: " 버그 ", body: "본문\n둘째 줄", labels: ["bug", " "], base: "main", head: "x", isDraft: true),
            rootPath: root)
        #expect(job.repo == "Me/App")
        #expect(job.arguments == ["issue", "create", "--repo", "Me/App", "--title", "버그", "--body", "본문\n둘째 줄", "--label", "bug"])
    }

    @Test func pullRequestArguments() throws {
        let root = try makeCheckout()
        // head를 안 주면 작업 트리의 현재 브랜치, base를 안 주면 저장소 기본(인자 없음)
        let plain = try GitHubPlanner.job(GitHubDraft(kind: .pr, title: "제목"), rootPath: root)
        #expect(plain.arguments == ["pr", "create", "--repo", "Me/App", "--title", "제목", "--body", "", "--head", "feat/x"])
        #expect(plain.directory == root)
        let full = try GitHubPlanner.job(
            GitHubDraft(kind: .pr, title: "제목", body: "글", labels: ["x"], base: "release", head: "main", isDraft: true), rootPath: root)
        #expect(full.arguments == ["pr", "create", "--repo", "Me/App", "--title", "제목", "--body", "글",
                                   "--head", "main", "--base", "release", "--draft"])
        // 다른 작업 트리(cwd)의 브랜치
        let other = try makeCheckout(branch: "main")
        let moved = try GitHubPlanner.job(GitHubDraft(kind: .pr, title: "제목"), rootPath: root, cwd: other)
        #expect(moved.draft.head == "main" && moved.directory == other && moved.repo == "Me/App")
    }

    @Test func planningFailures() throws {
        func error(_ draft: GitHubDraft, _ root: String) -> GitHubError? {
            do { _ = try GitHubPlanner.job(draft, rootPath: root); return nil } catch { return error as? GitHubError }
        }
        let issue = GitHubDraft(kind: .issue, title: "제목")
        #expect(error(issue, try makeCheckout(origin: nil)) == .noRemote)
        #expect(error(issue, "/nonexistent/waypoint-\(UUID().uuidString)") == .noRemote)
        #expect(error(issue, try makeCheckout(origin: "git@gitlab.com:me/app.git")) == .notGitHub("git@gitlab.com:me/app.git"))
        #expect(error(GitHubDraft(kind: .issue, title: "  "), try makeCheckout()) == .failed("제목이 비어 있음"))
        // push하지 않은 브랜치: 현재 브랜치든 준 브랜치든
        #expect(error(GitHubDraft(kind: .pr, title: "제목"), try makeCheckout(branch: "wip")) == .branchNotPushed("wip"))
        #expect(error(GitHubDraft(kind: .pr, title: "제목", head: "nope"), try makeCheckout()) == .branchNotPushed("nope"))
        #expect(GitHubError.branchNotPushed("wip").message == "브랜치가 원격에 없음 — 먼저 push: wip")
    }

    @Test func runParsesCreatedURL() throws {
        let root = try makeCheckout()
        let gh = try FakeGH(stdout: "Creating pull request for feat/x into main in Me/App\n\nhttps://github.com/Me/App/pull/34\n")
        let job = try GitHubPlanner.job(GitHubDraft(kind: .pr, title: "제목", isDraft: true), rootPath: root)
        let created = try job.run(gh.cli()).get()
        #expect(created == GitHubCreated(kind: .pr, repo: "Me/App", number: 34, url: "https://github.com/Me/App/pull/34",
                                         title: "제목", state: .draft, branch: "feat/x"))
        #expect(gh.calls == [job.arguments])

        let issueGH = try FakeGH(stdout: "https://github.com/Me/App/issues/12\n")
        let issue = try GitHubPlanner.job(GitHubDraft(kind: .issue, title: "버그"), rootPath: root).run(issueGH.cli()).get()
        #expect(issue.number == 12 && issue.state == .open && issue.branch == nil)
    }

    @Test func runFailures() throws {
        let job = try GitHubPlanner.job(GitHubDraft(kind: .pr, title: "제목"), rootPath: try makeCheckout())
        func failure(_ cli: GitHubCLI) -> GitHubError? {
            if case .failure(let error) = job.run(cli) { return error }
            return nil
        }
        #expect(failure(GitHubCLI(executable: nil, environment: [:])) == .toolMissing)
        #expect(failure(try FakeGH(stderr: "To get started with GitHub CLI, please run:  gh auth login\n", status: 4).cli()) == .notLoggedIn)
        #expect(failure(try FakeGH(stderr: "You are not logged into any GitHub hosts.\n", status: 1).cli()) == .notLoggedIn)
        #expect(failure(try FakeGH(stderr: "pull request create failed: GraphQL: Head sha can't be blank\n", status: 1).cli())
                == .branchNotPushed("feat/x"))
        #expect(failure(try FakeGH(stderr: "could not add label: 'nope' not found\n", status: 1).cli())
                == .failed("could not add label: 'nope' not found"))
        #expect(failure(try FakeGH(stdout: "이상한 출력\n").cli()) == .failed("만든 주소를 읽지 못함"))
        let start = Date()
        #expect(failure(try FakeGH(stdout: "https://github.com/Me/App/pull/1\n", sleep: 5).cli(timeout: 0.5)) == .timedOut(0))
        #expect(Date().timeIntervalSince(start) < 4)
        #expect(GitHubError.timedOut(20).message == "20초 안에 끝나지 않음")
    }

    /// 화면에 그대로 보이는 문구에 만든 쪽 말이 없다.
    @Test func messagesAvoidToolWords() {
        let errors: [GitHubError] = [.toolMissing, .notLoggedIn, .noRemote, .notGitHub("x"), .noBranch,
                                     .branchNotPushed("b"), .timedOut(20), .failed("")]
        for error in errors {
            for word in ["gh ", "CLI", "MCP", "캐시"] { #expect(!error.message.contains(word), "\(error)") }
        }
    }
}

@Suite struct GitHubLogTests {
    static func created(_ kind: GitHubKind, _ number: Int, state: GitHubState = .open) -> GitHubCreated {
        GitHubCreated(kind: kind, repo: "Me/App", number: number,
                      url: "https://github.com/Me/App/\(kind == .pr ? "pull" : "issues")/\(number)",
                      title: "제목 \(number)", state: state, branch: kind == .pr ? "feat/x" : nil)
    }

    @Test func cardLinkRule() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let p = makeProject(ctx)
        let a = p.makeCard(in: ctx, title: "A", at: t0), b = p.makeCard(in: ctx, title: "B", at: t0)
        let c = p.makeCard(in: ctx, title: "C", at: t0)
        let session = makeSession(ctx, p, id: "s1")
        // 세션에 작업중 카드가 없으면 프로젝트에만
        #expect(GitHubLog.linkedCard(explicit: nil, session: session) == nil)
        CardLifecycle.attach(a, session, at: t0 + 1, in: ctx)
        #expect(GitHubLog.linkedCard(explicit: nil, session: session) === a)
        // 준 카드가 먼저
        #expect(GitHubLog.linkedCard(explicit: c, session: session) === c)
        // 작업중 카드가 둘이면 고르지 않는다
        CardLifecycle.attach(b, session, at: t0 + 2, in: ctx)
        #expect(GitHubLog.linkedCard(explicit: nil, session: session) == nil)
        #expect(GitHubLog.linkedCard(explicit: nil, session: nil) == nil)
    }

    @Test func recordAndRead() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let p = makeProject(ctx), other = makeProject(ctx, key: "OTH", name: "other")
        let card = p.makeCard(in: ctx, title: "카드", body: "본문", criteria: [Criterion("하나", isDone: true), Criterion("둘")], at: t0)
        let session = makeSession(ctx, p, id: "s1")
        let issue = GitHubLog.record(Self.created(.issue, 12), project: p, card: card, session: session, at: t0 + 1, in: ctx)
        let pr = GitHubLog.record(Self.created(.pr, 34, state: .draft), project: p, card: nil, session: nil, at: t0 + 2, in: ctx)
        GitHubLog.record(Self.created(.issue, 1), project: other, card: nil, session: nil, at: t0 + 3, in: ctx)
        try ctx.save()

        #expect(issue.type == .githubIssue && pr.type == .githubPR)
        #expect(issue.payloadValues == ["number": 12, "url": "https://github.com/Me/App/issues/12", "title": "제목 12",
                                        "state": "open", "repo": "Me/App", "provider": "claude"])
        #expect(pr.payloadValues["branch"] == "feat/x" && pr.payloadValues["provider"] == nil)
        // 옛 앱은 모르는 종류를 메모로 읽는다: 메모 글 키를 두지 않는다
        #expect(issue.payloadValues["text"] == nil)
        // 저장 형식은 그대로(종류 문자열만 새로)
        #expect(issue.typeRaw == "github.issue" && pr.typeRaw == "github.pr")

        let items = GitHubLog.items(for: p)
        #expect(items.map(\.label) == ["PR #34", "이슈 #12"])
        #expect(items.map(\.cardID) == [nil, "LDG-1"])
        #expect(items[0].state == .draft && items[0].branch == "feat/x")
        #expect(GitHubLog.items(for: card).map(\.number) == [12])
        #expect(GitHubLog.items(in: ctx).count == 3)
        #expect(GitHubLog.openSummary(items) == "이슈 1 · PR 1")
        #expect(GitHubLog.openSummary([]) == nil)

        #expect(CardHistoryFormat.line(for: issue)?.text == "이슈 #12 열림 · 제목 12")
        #expect(ActivityEntryFormat.entry(pr)?.text == "PR #34 열림")
        #expect(ActivityEntryFormat.entry(pr)?.detail == "제목 34")

        let draft = GitHubLog.draft(for: card, kind: .pr)
        #expect(draft.title == "카드" && draft.body == "본문\n\n- [x] 하나\n- [ ] 둘")
    }
}

@Suite struct GitHubStatusCacheTests {
    static func item(_ kind: GitHubKind, _ number: Int, repo: String = "Me/App", at: Date = t0) -> GitHubItem {
        GitHubItem(id: UUID(), kind: kind, repo: repo, number: number, url: "u", title: "옛 제목", state: .open,
                   branch: nil, projectID: nil, cardID: nil, at: at)
    }

    @Test func staleAfterFiveMinutes() {
        let issue = Self.item(.issue, 12), pr = Self.item(.pr, 34)
        var cache = GitHubStatusCache()
        // 확인한 적이 없으면 연 시각부터 센다
        #expect(cache.stale([issue, pr], now: t0 + 299).isEmpty)
        #expect(cache.stale([issue, pr], now: t0 + 300).count == 2)
        cache.merge([issue.key: .init(state: .closed, title: "새 제목", checkedAt: t0 + 1000)])
        #expect(cache.stale([issue, pr], now: t0 + 1299).map(\.number) == [34])
        #expect(cache.stale([issue, pr], now: t0 + 1300).count == 2)
        let applied = cache.applied(to: [issue, pr])
        #expect(applied[0].state == .closed && applied[0].title == "새 제목")
        #expect(applied[1].state == .open && applied[1].title == "옛 제목")
        #expect(GitHubLog.openSummary(applied) == "이슈 0 · PR 1")
    }

    @Test func savesPrivateFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-ghcache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(GitHubStatusCache.load(directory: folder) == GitHubStatusCache())
        let cache = GitHubStatusCache(entries: ["me/app#pr#34": .init(state: .merged, title: "제목", checkedAt: t0)])
        try cache.save(directory: folder)
        let path = folder.appendingPathComponent("github-cache.json").path
        let mode = try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue == 0o600)
        #expect(GitHubStatusCache.load(directory: folder) == cache)
        #expect(RecordScope.localItems.flatMap(\.paths).contains(GitHubStatusCache.fileName))
    }

    @Test func oneQueryForEverything() throws {
        let items = [Self.item(.issue, 12), Self.item(.pr, 34), Self.item(.pr, 34), Self.item(.pr, 5, repo: "other/lib")]
        let args = GitHubStatusQuery.arguments(for: items)
        #expect(Array(args.prefix(3)) == ["api", "graphql", "-f"])
        #expect(args[3] == "query=query { r0: repository(owner: \"me\", name: \"app\") { i12: issue(number: 12) { state title } "
                + "p34: pullRequest(number: 34) { state title isDraft } } "
                + "r1: repository(owner: \"other\", name: \"lib\") { p5: pullRequest(number: 5) { state title isDraft } } }")

        let response = """
        {"data":{"r0":{"i12":{"state":"CLOSED","title":"버그"},"p34":{"state":"OPEN","title":"기능","isDraft":true}},
        "r1":{"p5":{"state":"MERGED","title":"합침","isDraft":false}}}}
        """
        let gh = try FakeGH(stdout: response)
        let entries = try GitHubStatusQuery.refresh(items, cli: gh.cli(), now: t0 + 9).get()
        #expect(gh.calls.count == 1)
        #expect(entries["me/app#issue#12"] == .init(state: .closed, title: "버그", checkedAt: t0 + 9))
        #expect(entries["me/app#pr#34"]?.state == .draft)
        #expect(entries["other/lib#pr#5"]?.state == .merged)
        // 지워진 것이 섞여 오류가 나도 읽힌 것은 쓴다
        let partial = try FakeGH(stdout: #"{"data":{"r0":{"i12":{"state":"OPEN","title":"버그"},"p34":null}},"errors":[{}]}"#, status: 1)
        #expect(try GitHubStatusQuery.refresh(items, cli: partial.cli(), now: t0).get().keys.sorted() == ["me/app#issue#12"])
        if case .success = GitHubStatusQuery.refresh(items, cli: try FakeGH(stderr: "gh auth login", status: 4).cli()) {
            Issue.record("로그인 안 됨이 성공으로 읽힘")
        }
    }
}

/// MCP 도구: 미룬 응답 경로(`handleDeferred`)로 부른다.
@Suite struct GitHubToolTests {
    /// 바깥 호출을 그 자리에서 돌려 결과를 바로 받는다.
    static func call(_ h: MCPHarness, _ name: String, _ arguments: JSONValue) throws -> (JSONValue, Bool) {
        try h.context.save()
        h.server.background = { $0() }
        h.server.resume = { $0() }
        var reply: JSONValue?
        let taken = h.server.handleDeferred([
            "jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments],
        ]) { reply = $0 }
        #expect(taken)
        let result = try #require(reply?["result"])
        let text = try #require(result["content"]?.arrayValue?.first?["text"]?.stringValue)
        return (try #require(JSONValue.parse(Data(text.utf8))), result["isError"]?.boolValue ?? false)
    }

    static func harness(_ gh: FakeGH, root: String? = nil) throws -> MCPHarness {
        let h = try MCPHarness()
        h.project.rootPath = try root ?? makeCheckout()
        h.server.tools.github = gh.cli()
        return h
    }

    @Test func toolsAreListedAndOnlyTheseAreDeferred() throws {
        let names = MCPTools.definitions.map(\.name)
        #expect(MCPTools.deferredTools.isSubset(of: Set(names)))
        #expect(MCPTools.deferredTools == ["github_issue_create", "github_pr_create"])
        let h = try MCPHarness()
        // 다른 도구·메서드는 맡지 않는다(평소 경로 그대로)
        for message: JSONValue in [
            ["jsonrpc": "2.0", "id": 1, "method": "ping"],
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "card_list", "arguments": ["project": "PRB"]]],
            ["jsonrpc": "2.0", "method": "tools/call", "params": ["name": "github_issue_create", "arguments": [:]]],
        ] {
            #expect(!h.server.handleDeferred(message) { _ in Issue.record("맡지 않은 요청에 응답") })
        }
        // 배치로 오면 평소 경로가 오류로 답한다
        let (value, isError) = try h.call("github_issue_create", ["project": "PRB", "title": "x"])
        #expect(isError && value["error"]?.stringValue?.contains("배치") == true)
    }

    @Test func issueLinksToGivenCard() throws {
        let gh = try FakeGH(stdout: "https://github.com/Me/App/issues/12\n")
        let h = try Self.harness(gh)
        _ = try h.ok("card_create", ["project": "PRB", "title": "카드"])
        let (value, isError) = try Self.call(h, "github_issue_create", [
            "project": "PRB", "title": "버그", "body": "본문", "labels": ["bug"], "cardId": "PRB-1",
            "sessionId": .string(MCPHarness.sessionID),
        ])
        #expect(!isError, "\(value.serializedString)")
        #expect(value == ["number": 12, "url": "https://github.com/Me/App/issues/12", "title": "버그", "state": "open", "cardId": "PRB-1"])
        #expect(gh.calls == [["issue", "create", "--repo", "Me/App", "--title", "버그", "--body", "본문", "--label", "bug"]])
        let card = try #require(h.card(1))
        let event = try #require(events(card, .githubIssue).first)
        #expect(event.session === h.session && event.project === h.project)
        #expect(event.payloadValues["provider"] == "claude")
        // 카드 상태는 그대로
        #expect(card.status == .next)
        #expect(h.context.hasChanges == false)
    }

    @Test func pullRequestFollowsSessionCard() throws {
        let gh = try FakeGH(stdout: "https://github.com/Me/App/pull/34\n")
        let h = try Self.harness(gh)
        _ = try h.ok("card_create", ["project": "PRB", "title": "카드"])
        // 작업중 카드가 없으면 프로젝트에만
        var (value, _) = try Self.call(h, "github_pr_create", ["project": "PRB", "title": "PR", "draft": true,
                                                               "sessionId": .string(MCPHarness.sessionID)])
        #expect(value["cardId"] == nil && value["state"] == "draft")
        #expect(gh.calls.last == ["pr", "create", "--repo", "Me/App", "--title", "PR", "--body", "", "--head", "feat/x", "--draft"])
        #expect(GitHubLog.items(for: h.project).map(\.cardID) == [nil])
        // 작업중 카드가 하나면 그 카드에
        _ = try h.ok("card_start", ["id": "PRB-1", "sessionId": .string(MCPHarness.sessionID)])
        (value, _) = try Self.call(h, "github_pr_create", ["project": "PRB", "title": "PR", "base": "main", "head": "main",
                                                           "sessionId": .string(MCPHarness.sessionID)])
        #expect(value["cardId"] == "PRB-1")
        #expect(gh.calls.last?.suffix(4) == ["--head", "main", "--base", "main"])
        #expect(events(try #require(h.card(1)), .githubPR).first?.payloadValues["branch"] == "main")
    }

    @Test func failuresReachTheCallerAndRecordNothing() throws {
        func message(_ h: MCPHarness, _ name: String = "github_pr_create", _ extra: [String: JSONValue] = [:]) throws -> String {
            var args: [String: JSONValue] = ["project": "PRB", "title": "제목"]
            for (key, value) in extra { args[key] = value }
            let (value, isError) = try Self.call(h, name, .object(args))
            #expect(isError)
            return value["error"]?.stringValue ?? ""
        }
        let ok = try FakeGH(stdout: "https://github.com/Me/App/pull/1\n")
        // 도구가 없음
        let missing = try Self.harness(ok)
        missing.server.tools.github = GitHubCLI(executable: nil, environment: [:])
        #expect(try message(missing).contains("GitHub 도구가 없음"))
        // 로그인 안 됨
        let auth = try Self.harness(try FakeGH(stderr: "run: gh auth login", status: 4))
        #expect(try message(auth) == "GitHub에 로그인되어 있지 않음 (터미널에서 gh auth login)")
        // 원격이 GitHub이 아님 · 원격 없음
        #expect(try message(try Self.harness(ok, root: try makeCheckout(origin: "git@gitlab.com:me/app.git")), "github_issue_create")
                .hasPrefix("원격 저장소가 GitHub 주소가 아님"))
        #expect(try message(try Self.harness(ok, root: "/nonexistent/x")) == "이 프로젝트 폴더에 원격 저장소가 없음")
        // push하지 않은 브랜치: 도구는 push하지 않는다
        let unpushed = try Self.harness(ok, root: try makeCheckout(branch: "wip"))
        #expect(try message(unpushed) == "브랜치가 원격에 없음 — 먼저 push: wip")
        #expect(ok.calls.isEmpty)
        // 시간 초과
        let slow = try Self.harness(try FakeGH(stdout: "https://github.com/Me/App/pull/1\n", sleep: 5))
        slow.server.tools.github.timeout = 0.4
        #expect(try message(slow) == "0초 안에 끝나지 않음")
        // 다른 프로젝트의 카드 · 없는 프로젝트
        #expect(try message(auth, "github_issue_create", ["cardId": "ZZZ-1"]).contains("카드 없음"))
        #expect(try message(auth, "github_issue_create", ["project": "NOPE"]).contains("프로젝트 없음"))
        for h in [missing, auth, unpushed, slow] {
            #expect(GitHubLog.items(in: h.context).isEmpty)
        }
    }

    /// 바깥 호출이 도는 동안 같은 서버가 다른 요청(훅·MCP가 쓰는 큐)을 바로 처리한다.
    @Test func otherRequestsAreNotHeldWhileWaiting() async throws {
        let gh = try FakeGH(stdout: "https://github.com/Me/App/issues/12\n", sleep: 1.5)
        let h = try MCPHarness()
        h.project.rootPath = try makeCheckout()
        try h.context.save()
        h.server.tools.github = gh.cli()
        // 응답은 이 테스트가 쥔 큐(앱의 메인 큐 자리)로 돌아온다
        let queue = DispatchQueue(label: "waypoint.test.context")
        h.server.resume = { work in queue.async(execute: work) }
        let server = UncheckedSendable(h.server)
        let start = Date()
        let reply: JSONValue = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let taken = server.value.handleDeferred([
                    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
                    "params": ["name": "github_issue_create", "arguments": ["project": "PRB", "title": "버그"]],
                ]) { continuation.resume(returning: $0) }
                // 맡자마자 돌아오고, 그 큐에서 다른 요청이 바로 처리된다
                let returned = Date().timeIntervalSince(start)
                let ping = server.value.handle(["jsonrpc": "2.0", "id": 2, "method": "ping"])
                let list = server.value.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                                "params": ["name": "card_list", "arguments": ["project": "PRB"]]])
                let handled = Date().timeIntervalSince(start)
                if !taken || ping?["result"] == nil || list?["result"]?["isError"] != false || returned > 0.5 || handled > 0.5 {
                    continuation.resume(throwing: MCPToolError("대기 중 다른 요청이 밀림: \(returned) \(handled)"))
                }
            }
        }
        #expect(Date().timeIntervalSince(start) >= 1.4)
        #expect(reply["result"]?["isError"] == false)
        #expect(queue.sync { GitHubLog.items(in: h.context).map(\.number) } == [12])
    }
}

@Suite(.serialized) struct GitHubServerTests {
    @Test func routerPicksOnlySingleDeferredCalls() {
        func request(_ body: String, method: String = "POST", headers: [String: String] = [:]) -> HTTPRequest {
            HTTPRequest(method: method, path: "/mcp", headers: headers, body: Data(body.utf8))
        }
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"github_pr_create","arguments":{}}}"#
        #expect(MCPRouter.deferredCall(request(call)) != nil)
        #expect(MCPRouter.deferredCall(request("[\(call)]")) == nil)
        #expect(MCPRouter.deferredCall(request(call, method: "GET")) == nil)
        #expect(MCPRouter.deferredCall(request(call, headers: ["origin": "https://evil.example"])) == nil)
        #expect(MCPRouter.deferredCall(request(call, headers: ["mcp-protocol-version": "1999-01-01"])) == nil)
        #expect(MCPRouter.deferredCall(request(call.replacingOccurrences(of: "github_pr_create", with: "card_list"))) == nil)
        #expect(MCPRouter.deferredCall(request("{")) == nil)
    }

    /// 미룬 응답을 기다리는 동안 훅 요청은 메인 액터에서 바로 답을 받는다.
    @MainActor @Test func hookAnswersWhileDeferredResponseIsPending() async throws {
        let port = UInt16.random(in: 49200...49900)
        let server = LocalServer(port: port) { _ in .text("main") }
        server.deferredHandler = { request, send in
            guard request.path == "/slow" else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { send(.text("late")) }
            return true
        }
        server.start()
        defer { server.stop() }
        for _ in 0..<100 where server.state != .ready { try await Task.sleep(for: .milliseconds(20)) }
        try #require(server.state == .ready)

        let slow = Task.detached { try await LocalServerTests.post(port, "/slow") }
        try await Task.sleep(for: .milliseconds(200))
        let hook = try await LocalServerTests.post(port, "/hooks/Stop")
        #expect(hook.status == 200 && hook.body == "main")
        #expect(hook.seconds < 0.5, "훅이 미룬 응답을 기다렸다: \(hook.seconds)초")
        let late = try await slow.value
        #expect(late.body == "late" && late.seconds >= 1.4)
        #expect(hook.finished < late.finished)
    }
}
#endif
