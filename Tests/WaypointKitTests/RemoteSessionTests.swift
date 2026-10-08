import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 원격(SSH)·개발 컨테이너 세션 수집(TRK-53): 원격 주소 정규화, 같은 원격 주소의 등록 프로젝트에 잇기,
/// 상대 경로·체크아웃 기준, `/hooks/replay`와 재수신 중복 방지, MCP `project_resolve(remote)`.
@Suite struct RemoteSessionTests {
    static let origin = "git@github.com:me/ledger.git"
    static let remoteRoot = "/home/dev/ledger"
    static let sessionID = "remote-session-1"

    /// LDG(`/Users/me/dev/ledger`, origin = github.com/me/ledger)를 갖춘 처리기. `origins`: 로컬 폴더 → origin 원문.
    struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let processor: HookProcessor
        let project: Project

        init(onDisk: Bool = false, origins: [String: String] = ["/Users/me/dev/ledger": RemoteSessionTests.origin],
             checkouts: [String: String] = [:], existing: Set<String> = []) throws {
            if onDisk {
                container = try makeDiskContainer("remote")
                context = ModelContext(container)
            } else {
                (container, context) = try makeContext()
            }
            let project = Project(key: "LDG", name: "가계부 앱", rootPath: "~/dev/ledger", createdAt: t0)
            context.insert(project)
            try context.save()
            self.project = project
            processor = HookProcessor(context: context, home: "/Users/me", gitBranch: { _ in "local-branch" },
                                      checkoutRoot: { _ in "/Users/me/dev/ledger" })
            processor.localOrigin = { root in
                origins[root].flatMap { GitRemoteURL.normalize($0) }
                    .map { LocalOrigin(checkout: checkouts[root] ?? root, url: $0) }
            }
            processor.pathExists = { existing.contains($0) }
        }

        func add(_ key: String, _ root: String, archived: Bool = false) throws -> Project {
            let p = Project(key: key, name: key, rootPath: root, createdAt: t0)
            if archived { p.archivedAt = t0 }
            context.insert(p)
            try context.save()
            return p
        }

        func session(_ id: String = RemoteSessionTests.sessionID) throws -> Session? {
            try context.fetch(FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id })).first
        }

        func fileChanges() throws -> [Event] {
            try context.fetch(FetchDescriptor<Event>()).filter { $0.type == .fileChanged }
        }
    }

    static func remoteField(root: String = remoteRoot, origin: String = origin, branch: String? = "feat/remote",
                            host: String? = "devbox") -> [String: Any] {
        var field: [String: Any] = ["origin": origin, "root": root]
        if let branch { field["branch"] = branch }
        if let host { field["host"] = host }
        return field
    }

    static func payload(_ event: String, cwd: String = remoteRoot + "/src", remote: [String: Any]? = remoteField(),
                        extra: [String: Any] = [:]) -> Data {
        var object: [String: Any] = ["session_id": sessionID, "cwd": cwd, "hook_event_name": event]
        if let remote { object["waypoint_remote"] = remote }
        object.merge(extra) { $1 }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func edit(_ path: String, id: String = "toolu_remote_1", cwd: String = remoteRoot + "/src",
                     remote: [String: Any]? = remoteField()) -> Data {
        payload("PostToolUse", cwd: cwd, remote: remote, extra: [
            "tool_name": "Edit", "tool_use_id": id,
            "tool_input": ["file_path": path, "old_string": "a\n", "new_string": "b\nc\n"],
        ])
    }

    // MARK: - 원격 주소 정규화

    @Test func normalizesEquivalentRemoteURLs() {
        let same = ["git@github.com:me/ledger.git", "https://github.com/me/ledger", "https://github.com/me/ledger.git/",
                    "ssh://git@github.com/me/ledger.git", "ssh://git@github.com:22/me/ledger", "https://user:tok@GitHub.com/Me/Ledger.git",
                    "git://github.com/me/ledger.git", " git@github.com:me/ledger.git\n"]
        for raw in same { #expect(GitRemoteURL.normalize(raw) == "github.com/me/ledger", "\(raw)") }
        #expect(GitRemoteURL.normalize("git@gitlab.com:me/ledger.git") == "gitlab.com/me/ledger")
        #expect(GitRemoteURL.normalize("/srv/git/ledger.git") == "/srv/git/ledger")
        #expect(GitRemoteURL.normalize("file:///srv/git/ledger.git") == "/srv/git/ledger")
        #expect(GitRemoteURL.normalize("") == nil)
        #expect(GitRemoteURL.normalize("https://github.com/") == nil)
    }

    @Test func readsOriginFromGitConfig() throws {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "upstream"]
        \turl = https://github.com/other/ledger
        [remote "origin"]
        \turl = git@github.com:me/ledger.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        """
        #expect(LocalOrigin.originURL(config: config) == "git@github.com:me/ledger.git")
        #expect(LocalOrigin.originURL(config: "[remote \"upstream\"]\n\turl = x") == nil)

        // 등록 폴더가 작업 트리의 하위 폴더여도 작업 트리 최상위를 찾는다. git 명령 없이 .git/config만 읽는다.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-origin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("app"), withIntermediateDirectories: true)
        try config.write(to: root.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        let found = try #require(LocalOrigin.read(rootPath: root.appendingPathComponent("app").path))
        #expect(found.url == "github.com/me/ledger")
        #expect(found.checkout == root.path)
    }

    @Test func cacheReadsOncePerLifetime() {
        var reads = 0
        var now = t0
        let cache = LocalOriginCache(reader: { _ in reads += 1; return nil }, now: { now })
        _ = cache.origin(for: "/a"); _ = cache.origin(for: "/a")
        #expect(reads == 1)
        now = t0 + LocalOriginCache.lifetime + 1
        _ = cache.origin(for: "/a")
        #expect(reads == 2)
    }

    // MARK: - 잇기

    /// 원격 작업 트리의 세션이 같은 원격 주소의 등록 프로젝트에 이어진다. 세션 폴더·브랜치는 원격 값, 파일은 작업 트리 기준 상대 경로.
    @Test func linksRemoteSessionToProjectWithSameOrigin() throws {
        let h = try Harness()
        let text = h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart"), at: t0)
        #expect(text?.hasPrefix("Waypoint: LDG") == true)
        let session = try #require(try h.session())
        #expect(session.project === h.project)
        #expect(session.cwd == Self.remoteRoot + "/src")
        #expect(session.gitBranch == "feat/remote")

        h.processor.handle(event: "PostToolUse", json: Self.edit(Self.remoteRoot + "/src/OCR.swift"), at: t0 + 10)
        let change = try #require(try h.fileChanges().first)
        #expect(change.project === h.project)
        #expect(change.payloadValues["path"]?.stringValue == "src/OCR.swift")
        #expect(change.payloadValues["added"] == .int(2))
        // 같은 파일 작업 중 판정 열쇠: 원격 작업 트리(로컬 체크아웃과 다르다)
        #expect(change.payloadValues["checkout"]?.stringValue == "devbox:/home/dev/ledger")
    }

    @Test func doesNotLinkWhenTwoCheckoutsShareOrigin() throws {
        let h = try Harness(origins: ["/Users/me/dev/ledger": Self.origin, "/Users/me/other/ledger": "https://github.com/me/ledger"])
        _ = try h.add("LD2", "/Users/me/other/ledger")
        let text = h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart"), at: t0)
        #expect(try h.session() == nil)
        #expect(text?.contains("remote: \(Self.origin)") == true)
    }

    @Test func doesNotLinkWithoutMatchingOrigin() throws {
        let h = try Harness()
        h.processor.handle(event: "SessionStart",
                           json: Self.payload("SessionStart", remote: Self.remoteField(origin: "git@github.com:me/other.git")), at: t0)
        #expect(try h.session() == nil)
        // 원격 정보가 없는 훅(옛 스크립트·로컬)도 지금처럼 미등록 폴더
        h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart", remote: nil), at: t0)
        #expect(try h.session() == nil)
    }

    /// 모노레포: 한 작업 트리 안의 두 프로젝트는 같은 작업 트리라 잇고, 옮긴 경로에서 가까운 프로젝트가 고른다.
    /// 상대 경로는 그 프로젝트 폴더 기준이고 프로젝트 밖 파일은 남기지 않는다.
    @Test func monorepoProjectsInOneCheckoutPickNearest() throws {
        let checkout = "/Users/me/mono"
        let h = try Harness(origins: ["/Users/me/mono/app": Self.origin, "/Users/me/mono/web": Self.origin,
                                      "/Users/me/dev/ledger": "git@github.com:me/unrelated.git"],
                            checkouts: ["/Users/me/mono/app": checkout, "/Users/me/mono/web": checkout])
        let app = try h.add("APP", "/Users/me/mono/app")
        _ = try h.add("WEB", "/Users/me/mono/web")
        h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart", cwd: Self.remoteRoot + "/app/Sources"), at: t0)
        let session = try #require(try h.session())
        #expect(session.project === app)
        h.processor.handle(event: "PostToolUse", json: Self.edit(Self.remoteRoot + "/app/Sources/A.swift",
                                                                 cwd: Self.remoteRoot + "/app/Sources"), at: t0 + 1)
        h.processor.handle(event: "PostToolUse", json: Self.edit(Self.remoteRoot + "/README.md", id: "toolu_remote_2",
                                                                 cwd: Self.remoteRoot + "/app/Sources"), at: t0 + 2)
        let paths = try h.fileChanges().compactMap { $0.payloadValues["path"]?.stringValue }
        #expect(paths == ["Sources/A.swift"])
    }

    @Test func localFoldersAreNotRemapped() throws {
        // 등록 폴더 안의 훅은 원격 정보가 있어도 지금처럼 그 폴더로
        let h = try Harness()
        h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart", cwd: "/Users/me/dev/ledger/src",
                                                                     remote: Self.remoteField(root: "/Users/me/dev/ledger")), at: t0)
        let session = try #require(try h.session())
        #expect(session.cwd == "/Users/me/dev/ledger/src")
        #expect(session.gitBranch == "local-branch")
        // 원격 작업 트리 경로가 이 Mac에 있으면(로컬의 다른 클론) 잇지 않는다
        let other = try Harness(existing: ["/Users/me/clone/ledger"])
        other.processor.handle(event: "SessionStart", json: Self.payload("SessionStart", cwd: "/Users/me/clone/ledger",
                                                                         remote: Self.remoteField(root: "/Users/me/clone/ledger")), at: t0)
        #expect(try other.session() == nil)
    }

    @Test func archivedProjectWithSameOriginIsNotLinked() throws {
        let h = try Harness(origins: ["/Users/me/old/ledger": Self.origin])
        _ = try h.add("OLD", "/Users/me/old/ledger", archived: true)
        h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart"), at: t0)
        #expect(try h.session() == nil)
    }

    // MARK: - replay

    @Test func replayEndpointAppendsReadableLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        func request(_ body: String, method: String = "POST") -> HTTPRequest {
            HTTPRequest(method: method, path: HookRouter.replayPath, headers: [:], body: Data(body.utf8))
        }
        let good = #"{"event":"Stop","receivedAt":1,"trimmed":true,"payload":{"session_id":"s","cwd":"/w"}}"#
        let append: (Data) throws -> Outbox.AppendResult = { try Outbox.append($0, directory: dir) }

        #expect(HookRouter.respondReplay(to: request(good, method: "GET"), append: append).status == 405)
        #expect(HookRouter.respondReplay(to: request(""), append: append).status == 400)
        #expect(HookRouter.respondReplay(to: request("not json\n"), append: append).status == 400)
        let tooMany = Array(repeating: good, count: Outbox.replayLineLimit + 1).joined(separator: "\n")
        #expect(HookRouter.respondReplay(to: request(tooMany), append: append).status == 400)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(Outbox.fileName).path))

        let response = HookRouter.respondReplay(to: request(good + "\nbroken\n" + good + "\n"), append: append)
        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == #"{"accepted":2,"rejected":1}"#)
        let text = try String(contentsOf: dir.appendingPathComponent(Outbox.fileName), encoding: .utf8)
        #expect(text == good + "\n" + good + "\n")

        let failing = HookRouter.respondReplay(to: request(good)) { _ in throw Outbox.SaveFailed() }
        #expect(failing.status == 500)
    }

    /// 원격이 200을 받지 못해 같은 묶음을 다시 보내도(앱은 이미 붙였다) 파일 변경·요청 기록이 한 번만 남는다.
    /// replay 줄은 실시간 경로(`RemoteReplay.drain` → `HookProcessor.handle(_:)`)로 처리한다.
    @Test func replayedBatchTwiceRecordsOnce() throws {
        let h = try Harness(onDisk: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        func line(_ event: String, _ data: Data, at date: Date) -> String {
            #"{"event":"\#(event)","receivedAt":\#(Int(date.timeIntervalSince1970)),"trimmed":true,"payload":\#(String(decoding: data, as: UTF8.self))}"#
        }
        let prompt = Self.payload("UserPromptSubmit", extra: ["prompt": "원격에서 OCR 고치기", "prompt_id": "p-remote-1"])
        let batch = [line("SessionStart", Self.payload("SessionStart"), at: t0),
                     line("UserPromptSubmit", prompt, at: t0 + 5),
                     line("PostToolUse", Self.edit(Self.remoteRoot + "/src/OCR.swift"), at: t0 + 10)].joined(separator: "\n")
        for _ in 0..<2 {
            let result = try Outbox.append(Data(batch.utf8), directory: dir)
            #expect(result == Outbox.AppendResult(accepted: 3, rejected: 0))
            #expect(RemoteReplay.hasBacklog(directory: dir))
            let drained = RemoteReplay.drain(directory: dir, processor: h.processor, deadline: nil)
            #expect(drained.processed == 3 && !drained.retryPending && !drained.more)
            #expect(!RemoteReplay.hasBacklog(directory: dir))
        }
        let session = try #require(try h.session())
        #expect(session.project === h.project)
        #expect(try h.fileChanges().count == 1)
        let prompts = try h.context.fetch(FetchDescriptor<Event>())
            .filter { $0.type == .note && $0.payloadValues["kind"]?.stringValue == "user.prompt" }
        #expect(prompts.count == 1)
    }

    /// 시간 예산이 다 되면 남은 줄을 두고 멈추고(`more`), 다음 흡수가 그 줄부터 순서대로 이어 간다.
    @Test func drainWithDeadlinePausesAndResumesInOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-budget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = (0..<5).map { #"{"event":"Stop","receivedAt":\#($0),"payload":{"session_id":"s\#($0)"}}"# }
        _ = try Outbox.append(Data((lines.joined(separator: "\n") + "\n").utf8), directory: dir)
        var seen: [String] = []
        let record: (Outbox.Entry) throws -> Void = { entry in
            let object = try JSONSerialization.jsonObject(with: entry.payload) as? [String: Any]
            seen.append(object?["session_id"] as? String ?? "?")
        }
        // 이미 지난 시각: 한 줄만 처리하고 멈춘다
        let first = Outbox.drain(directory: dir, deadline: .distantPast, handle: record)
        #expect(first.processed == 1 && first.more && !first.retryPending)
        // 그사이 새로 온 줄은 남은 줄 뒤에 선다
        _ = try Outbox.append(Data(#"{"event":"Stop","receivedAt":9,"payload":{"session_id":"late"}}"#.utf8), directory: dir)
        let second = Outbox.drain(directory: dir, deadline: .distantPast, handle: record)
        #expect(second.processed == 1 && second.more)
        let rest = Outbox.drain(directory: dir, handle: record)
        #expect(rest.processed == 4 && !rest.more)
        #expect(seen == ["s0", "s1", "s2", "s3", "s4", "late"])
    }

    /// 남아 있던 처리 중 파일의 밀리초가 지금 시각 이상이어도 새로 온 줄은 그 뒤에 선다.
    @Test func drainKeepsLeftoverBeforeNewlyClaimedLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let leftover = dir.appendingPathComponent("\(Outbox.processingPrefix)9000000000000-\(UUID().uuidString).jsonl")
        try (#"{"event":"Stop","receivedAt":1,"payload":{"session_id":"early"}}"# + "\n")
            .write(to: leftover, atomically: true, encoding: .utf8)
        _ = try Outbox.append(Data(#"{"event":"Stop","receivedAt":9,"payload":{"session_id":"late"}}"#.utf8), directory: dir)
        var seen: [String] = []
        let result = Outbox.drain(directory: dir) { entry in
            let object = try JSONSerialization.jsonObject(with: entry.payload) as? [String: Any]
            seen.append(object?["session_id"] as? String ?? "?")
        }
        #expect(result.processed == 2 && !result.more && !result.retryPending)
        #expect(seen == ["early", "late"])
    }

    /// 흡수가 남은 동안 outbox 뒤에 세우는 실시간 훅: 블록이 필요 없는 이벤트만, 흡수가 읽는 한 줄 꼴로.
    @Test func liveHookLineMatchesOutboxFormat() throws {
        #expect(HookRouter.defersWhileDraining("Stop"))
        #expect(HookRouter.defersWhileDraining("SessionEnd"))
        #expect(!HookRouter.defersWhileDraining("SessionStart"))
        #expect(!HookRouter.defersWhileDraining("UserPromptSubmit"))
        let body = Self.payload("PostToolUse")
        let data = try #require(Outbox.line(event: "PostToolUse", provider: .codex, receivedAt: t0, pid: 4242, payload: body))
        #expect(data.last == UInt8(ascii: "\n"))
        let entry = try #require(Outbox.parse(line: Substring(String(decoding: data.dropLast(), as: UTF8.self))))
        #expect(entry.provider == .codex && entry.event == "PostToolUse" && entry.receivedAt == t0 && entry.processPid == 4242)
        let input = try #require(HookInput(event: entry.event, json: entry.payload, provider: entry.provider))
        #expect(input.remote?.root == Self.remoteRoot)
        #expect(Outbox.line(event: "Stop", provider: .claude, receivedAt: t0, pid: nil, payload: Data("[]".utf8)) == nil)
    }

    /// 다시 이어진 뒤 첫 훅(실시간)이 세션을 먼저 만들고 쌓인 이른 줄이 뒤에 들어와도 시작 시각·시작 기록은 가장 이른 훅의 것.
    @Test func lateEarlierHooksMoveSessionStartBack() throws {
        let h = try Harness()
        h.processor.handle(event: "Stop", json: Self.payload("Stop"), at: t0 + 100)
        h.processor.handle(event: "SessionStart", json: Self.payload("SessionStart", extra: ["source": "startup"]), at: t0,
                           delivers: false)
        let session = try #require(try h.session())
        #expect(session.startedAt == t0)
        let starts = (session.events ?? []).filter { $0.type == .sessionStart }
        #expect(starts.count == 1)
        #expect(starts.first?.at == t0)
        #expect(starts.first?.payloadValues["source"]?.stringValue == "startup")
        #expect(session.lastSeenAt == t0 + 100)
    }

    /// replay 저장 실패: 그 줄부터 남기고(`retryPending`) 다음 처리에서 이어 간다. 기록은 한 번만.
    @Test func replaySaveFailureKeepsLineForRetry() throws {
        let h = try Harness(onDisk: true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let edit = Self.edit(Self.remoteRoot + "/src/OCR.swift")
        let line = #"{"event":"PostToolUse","receivedAt":\#(Int(t0.timeIntervalSince1970)),"payload":\#(String(decoding: edit, as: UTF8.self))}"#
        _ = try Outbox.append(Data(line.utf8), directory: dir)
        struct DiskFull: Error {}
        h.processor.saveContext = { _ in throw DiskFull() }
        let failed = RemoteReplay.drain(directory: dir, processor: h.processor, deadline: nil)
        #expect(failed.retryPending && failed.processed == 0)
        #expect(RemoteReplay.hasBacklog(directory: dir))
        h.processor.saveContext = { try $0.save() }
        let retried = RemoteReplay.drain(directory: dir, processor: h.processor, deadline: nil)
        #expect(retried.processed == 1 && !retried.retryPending)
        #expect(try h.fileChanges().count == 1)
    }

    // MARK: - MCP

    @Test func projectResolveAcceptsRemoteOrigin() throws {
        let h = try Harness()
        let tools = MCPTools(context: h.context, home: "/Users/me")
        tools.localOrigin = h.processor.localOrigin
        func resolve(_ args: JSONValue) throws -> String? { try tools.call("project_resolve", args)["key"]?.stringValue }
        #expect(try resolve(["cwd": "/home/dev/ledger/src", "remote": "https://github.com/me/ledger"]) == "LDG")
        #expect(try resolve(["cwd": "/home/dev/ledger/src"]) == nil)
        #expect(try resolve(["cwd": "/home/dev/ledger/src", "remote": "git@github.com:me/other.git"]) == nil)
        // 등록 폴더면 remote와 상관없이 그 폴더
        #expect(try resolve(["cwd": "/Users/me/dev/ledger", "remote": "git@github.com:me/other.git"]) == "LDG")
        let h2 = try Harness(origins: ["/Users/me/dev/ledger": Self.origin, "/Users/me/other/ledger": Self.origin])
        _ = try h2.add("LD2", "/Users/me/other/ledger")
        let tools2 = MCPTools(context: h2.context, home: "/Users/me")
        tools2.localOrigin = h2.processor.localOrigin
        #expect(try tools2.call("project_resolve", ["cwd": "/home/dev/ledger", "remote": .string(Self.origin)]) == .null)
    }
}

/// 원격 모드 훅 스크립트가 쓴 outbox 줄을 앱이 읽어 원격 정보를 얻는지(실제 스크립트, 닫힌 포트).
@Suite struct RemoteOutboxScriptTests {
    @Test func remoteModeOutboxCarriesRemoteCheckout() throws {
        #if os(macOS)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-remote-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "ref: refs/heads/feat/remote\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "[remote \"origin\"]\n\turl = git@github.com:me/ledger.git\n"
            .write(to: repo.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        let support = base.appendingPathComponent("support")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [OutboxTrimTests.script.path, "Stop"]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "HOSTNAME": "devbox",
                               "WAYPOINT_PORT": "1", "WAYPOINT_REMOTE": "1", "WAYPOINT_SUPPORT_DIR": support.path]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        stdin.fileHandleForWriting.write(Data(#"{"session_id":"s","cwd":"\#(repo.path)/src","hook_event_name":"Stop"}"#.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let text = try String(contentsOf: support.appendingPathComponent(Outbox.fileName), encoding: .utf8)
        let first = try #require(text.split(separator: "\n").first)
        let entry = try #require(Outbox.parse(line: first))
        let input = try #require(HookInput(event: entry.event, json: entry.payload))
        #expect(input.remote == RemoteCheckout(origin: "git@github.com:me/ledger.git", root: repo.path,
                                               branch: "feat/remote", host: "devbox"))
        #expect(input.cwd == repo.path + "/src")
        #endif
    }
}
