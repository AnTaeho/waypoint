import Foundation
import SwiftData

/// `github_issue_create`·`github_pr_create`(TRK-68). 바깥 호출이 오래 걸려 세 토막으로 나눈다:
/// `githubPlan`(context의 액터) → `GitHubJob.run`(백그라운드) → `githubFinish`(context의 액터).
extension MCPTools {
    /// 응답을 미루는 도구(`MCPServer.handleDeferred`)
    public static let deferredTools: Set<String> = ["github_issue_create", "github_pr_create"]

    /// 백그라운드를 건너는 값. 모델 객체 대신 키·ID만 든다.
    struct GitHubPlan: Sendable {
        let job: GitHubJob
        let projectKey: String
        let cardID: String?
        let sessionID: String?
    }

    func githubPlan(_ name: String, _ args: JSONValue) throws -> GitHubPlan {
        let project = try resolveProject(args)
        let kind: GitHubKind = name == "github_pr_create" ? .pr : .issue
        var card: Card?
        if let cardID = optionalString(args, "cardId") {
            card = try findCard(cardID)
            guard card?.project === project else { throw MCPToolError("cardId는 같은 프로젝트 카드여야 함") }
        }
        let labels = try args["labels"].flatMap { raw -> [String]? in
            if raw.isNull { return nil }
            guard let items = raw.arrayValue, items.allSatisfy({ $0.stringValue != nil }) else {
                throw MCPToolError("labels는 문자열 배열")
            }
            return items.compactMap(\.stringValue)
        } ?? []
        let draft = GitHubDraft(
            kind: kind, title: try requiredString(args, "title"), body: optionalString(args, "body") ?? "",
            labels: labels, base: optionalString(args, "base"), head: optionalString(args, "head"),
            isDraft: args["draft"]?.boolValue ?? false
        )
        guard github.executable != nil else { throw MCPToolError(GitHubError.toolMissing) }
        do {
            let job = try GitHubPlanner.job(draft, rootPath: project.rootPath, cwd: optionalString(args, "cwd"), home: home)
            return GitHubPlan(job: job, projectKey: project.key, cardID: card?.displayID,
                              sessionID: optionalString(args, "sessionId"))
        } catch let error as GitHubError {
            throw MCPToolError(error)
        }
    }

    /// 만든 것을 기록한다. 그사이 카드·프로젝트가 사라졌으면 남은 쪽에만 잇는다.
    func githubFinish(_ plan: GitHubPlan, _ created: GitHubCreated) throws -> JSONValue {
        var json: [String: JSONValue] = [
            "number": JSONValue(created.number), "url": .string(created.url), "title": .string(created.title),
            "state": .string(created.state.rawValue),
        ]
        guard let project = allProjects().first(where: { $0.key == plan.projectKey }) else { return .object(json) }
        let session = plan.sessionID.flatMap(fetchSession)
        let explicit = plan.cardID.flatMap { try? findCard($0) }
        let card = GitHubLog.linkedCard(explicit: explicit, session: session?.project === project ? session : nil)
        GitHubLog.record(created, project: project, card: card, session: session, at: now(), in: context)
        if let card { json["cardId"] = .string(card.displayID) }
        return .object(json)
    }
}

extension MCPToolError {
    init(_ error: GitHubError) {
        self.init(error.hint.map { "\(error.message) (\($0))" } ?? error.message)
    }
}

/// 한 액터에서만 쓰는 값을 백그라운드 클로저에 실어 되돌려 보낼 때 쓴다.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
