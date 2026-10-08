import Foundation

/// 이슈·PR의 마지막으로 확인한 상태. 이 Mac의 파일에만 둔다(저장소·iCloud에 넣지 않는다).
public struct GitHubStatusCache: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var state: GitHubState
        public var title: String
        public var checkedAt: Date
    }

    public static let fileName = "github-cache.json"
    /// 이보다 오래된 상태는 다시 읽는다
    public static let lifetime: TimeInterval = 5 * 60

    public var entries: [String: Entry] = [:]

    public init(entries: [String: Entry] = [:]) { self.entries = entries }

    public static func load(directory: URL) -> GitHubStatusCache {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let cache = try? decoder.decode(GitHubStatusCache.self, from: data) else { return GitHubStatusCache() }
        return cache
    }

    public func save(directory: URL) throws {
        let url = directory.appendingPathComponent(Self.fileName)
        try Self.encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// 다시 읽어야 하는 것. 확인한 적이 없으면 연 시각을 확인 시각으로 본다.
    public func stale(_ items: [GitHubItem], now: Date) -> [GitHubItem] {
        items.filter { now.timeIntervalSince(entries[$0.key]?.checkedAt ?? $0.at) >= Self.lifetime }
    }

    /// 확인한 상태·제목을 덮어쓴 목록
    public func applied(to items: [GitHubItem]) -> [GitHubItem] {
        items.map { item in
            guard let entry = entries[item.key] else { return item }
            var copy = item
            copy.state = entry.state
            if !entry.title.isEmpty { copy.title = entry.title }
            return copy
        }
    }

    public mutating func merge(_ fresh: [String: Entry]) {
        entries.merge(fresh) { _, new in new }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 여러 이슈·PR의 상태를 호출 한 번으로 읽는다(GraphQL 별칭).
public enum GitHubStatusQuery {
    public static func arguments(for items: [GitHubItem]) -> [String] {
        ["api", "graphql", "-f", "query=\(query(for: items))"]
    }

    static func query(for items: [GitHubItem]) -> String {
        let repos = Dictionary(grouping: items, by: { $0.repo.lowercased() }).sorted { $0.key < $1.key }
        let blocks = repos.enumerated().compactMap { index, group -> String? in
            let parts = group.key.split(separator: "/")
            guard parts.count == 2 else { return nil }
            var seen = Set<String>()
            let fields = group.value.sorted { $0.number < $1.number }.filter { seen.insert($0.key).inserted }.map { item in
                item.kind == .issue
                    ? "i\(item.number): issue(number: \(item.number)) { state title }"
                    : "p\(item.number): pullRequest(number: \(item.number)) { state title isDraft }"
            }
            return "r\(index): repository(owner: \(quoted(parts[0])), name: \(quoted(parts[1]))) { \(fields.joined(separator: " ")) }"
        }
        return "query { \(blocks.joined(separator: " ")) }"
    }

    /// 응답 JSON → 열쇠별 상태. 지워졌거나 못 읽은 것은 빠진다.
    public static func parse(_ stdout: String, items: [GitHubItem], now: Date) -> [String: GitHubStatusCache.Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
              let data = root["data"] as? [String: Any] else { return [:] }
        let repos = Dictionary(grouping: items, by: { $0.repo.lowercased() }).sorted { $0.key < $1.key }
        var result: [String: GitHubStatusCache.Entry] = [:]
        for (index, group) in repos.enumerated() {
            guard let repo = data["r\(index)"] as? [String: Any] else { continue }
            for item in group.value {
                let alias = (item.kind == .issue ? "i" : "p") + String(item.number)
                guard let node = repo[alias] as? [String: Any], let raw = node["state"] as? String else { continue }
                result[item.key] = .init(state: state(raw, isDraft: node["isDraft"] as? Bool ?? false),
                                         title: node["title"] as? String ?? "", checkedAt: now)
            }
        }
        return result
    }

    static func state(_ raw: String, isDraft: Bool) -> GitHubState {
        switch raw.uppercased() {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: isDraft ? .draft : .open
        }
    }

    /// 백그라운드에서 부른다. 일부만 읽혀도 읽힌 것은 돌려준다.
    public static func refresh(_ items: [GitHubItem], cli: GitHubCLI, now: Date = Date()) -> Result<[String: GitHubStatusCache.Entry], GitHubError> {
        guard !items.isEmpty else { return .success([:]) }
        do {
            let output = try cli.run(arguments(for: items))
            let entries = parse(output.stdout, items: items, now: now)
            if entries.isEmpty, output.status != 0 { return .failure(GitHubCLI.error(for: output)) }
            return .success(entries)
        } catch let error as GitHubError {
            return .failure(error)
        } catch {
            return .failure(.failed(String(describing: error)))
        }
    }

    private static func quoted(_ text: Substring) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
