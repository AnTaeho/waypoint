import Foundation

/// Codex 사용량. Codex가 대화마다 남기는 기록 파일(`<CODEX_HOME>/sessions/YYYY/MM/DD/rollout-*.jsonl`)의
/// `token_count` 이벤트에 붙는 `rate_limits`를 읽는다. 앱은 이 파일만 읽고 네트워크를 쓰지 않는다.
///
/// 한 줄 형식(필요한 부분만):
/// `{"timestamp":"2026-10-01T02:23:33.438Z","type":"event_msg","payload":{"type":"token_count",
///   "rate_limits":{"limit_id":"codex","primary":{"used_percent":95.0,"window_minutes":300,"resets_at":1790836235},
///   "secondary":{"used_percent":39.0,"window_minutes":10080,"resets_at":1791350556},...}}}`
/// 같은 파일에 `limit_id`가 `premium`·`base_model_inference`인 다른 한도도 섞여 오므로 `codex`(또는 없음)만 받는다.
public enum CodexUsage {

    public static let limitID = "codex"

    // MARK: 한 줄

    /// 기록 한 줄에서 Codex 한도를 읽는다. 한도가 없거나 다른 한도면 nil.
    /// - Parameter fallbackCapturedAt: 줄에 `timestamp`가 없을 때 쓸 시각(보통 파일 수정 시각).
    public static func parseLine(_ line: Data, fallbackCapturedAt: Date? = nil) -> UsageGroup? {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return nil }
        let payload = (root["payload"] as? [String: Any]) ?? root
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        if let id = limits["limit_id"], !(id is NSNull) {
            guard (id as? String) == limitID else { return nil }
        }
        let windows = ["primary", "secondary"].compactMap { limit(limits[$0]) }
        guard !windows.isEmpty else { return nil }
        guard let capturedAt = UsageSnapshot.date(root["timestamp"]) ?? fallbackCapturedAt else { return nil }
        return UsageGroup(tool: .codex, limits: windows, capturedAt: capturedAt)
    }

    private static func limit(_ value: Any?) -> UsageGroup.Limit? {
        guard let dict = value as? [String: Any],
              let percent = UsageSnapshot.number(dict["used_percent"]),
              let minutes = UsageSnapshot.number(dict["window_minutes"]), minutes > 0
        else { return nil }
        let window = UsageSnapshot.Window(usedPercent: percent, resetsAt: UsageSnapshot.date(dict["resets_at"]))
        return UsageGroup.Limit(minutes: Int(minutes.rounded()), window: window)
    }

    // MARK: 파일 끝부분

    /// 파일 끝부분에서 마지막 Codex 한도를 찾는다. 첫 줄은 잘렸을 수 있어(`isPartialStart`) 버리고,
    /// 마지막 줄이 쓰는 중이라 깨졌으면 그 줄은 읽지 못해 건너뛴다.
    public static func latest(inTail data: Data, isPartialStart: Bool, fallbackCapturedAt: Date? = nil) -> UsageGroup? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if isPartialStart, !lines.isEmpty { lines.removeFirst() }
        let marker = Data("rate_limits".utf8)
        for line in lines.reversed() where line.range(of: marker) != nil {
            if let group = parseLine(Data(line), fallbackCapturedAt: fallbackCapturedAt) { return group }
        }
        return nil
    }

    // MARK: 폴더

    /// `CODEX_HOME`이 있으면 `$CODEX_HOME/sessions`, 없으면 `~/.codex/sessions`.
    public static func sessionsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public struct Candidate: Equatable, Sendable {
        public var url: URL
        public var modified: Date
    }

    /// 최근 날짜 폴더(`YYYY/MM/DD`, 이름순으로 최근 `days`개)의 `rollout-*.jsonl`을 수정 시각이 최근인 순으로.
    /// 폴더 이름은 기록한 기기의 날짜라 오늘 날짜를 계산하지 않고 이름 목록에서 고른다.
    public static func candidates(in sessions: URL, days: Int = 7, fileManager: FileManager = .default) -> [Candidate] {
        func children(_ url: URL) -> [String] {
            ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []).sorted(by: >)
        }
        var dayFolders: [URL] = []
        outer: for year in children(sessions) where year.allSatisfy(\.isNumber) {
            let yearURL = sessions.appendingPathComponent(year)
            for month in children(yearURL) where month.allSatisfy(\.isNumber) {
                let monthURL = yearURL.appendingPathComponent(month)
                for day in children(monthURL) where day.allSatisfy(\.isNumber) {
                    dayFolders.append(monthURL.appendingPathComponent(day))
                    if dayFolders.count >= days { break outer }
                }
            }
        }
        var found: [Candidate] = []
        for folder in dayFolders {
            for name in children(folder) where name.hasPrefix("rollout-") && name.hasSuffix(".jsonl") {
                let url = folder.appendingPathComponent(name)
                guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                else { continue }
                found.append(Candidate(url: url, modified: modified))
            }
        }
        return found.sorted { $0.modified > $1.modified }
    }

    /// 먼저 이만큼 읽고, 못 찾으면 더 크게 한 번 더 읽는다(도구 출력 줄은 아주 길 수 있다).
    public static let tailSizes = [256 * 1024, 4 * 1024 * 1024]
    /// 이만큼의 파일까지만 훑는다.
    public static let maxFiles = 5

    /// 파일 끝부분에서 마지막 Codex 한도. 읽지 못하면 nil.
    public static func load(from candidate: Candidate) -> UsageGroup? {
        guard let handle = try? FileHandle(forReadingFrom: candidate.url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        for tail in tailSizes {
            let start = size > UInt64(tail) ? size - UInt64(tail) : 0
            guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
            if let group = latest(inTail: data, isPartialStart: start > 0, fallbackCapturedAt: candidate.modified) {
                return group
            }
            if start == 0 { break }
        }
        return nil
    }

    /// 최근 파일부터 차례로 훑어 처음 찾은 Codex 한도와 그 파일.
    public static func latest(in candidates: [Candidate]) -> (group: UsageGroup, source: Candidate)? {
        for candidate in candidates.prefix(maxFiles) {
            if let group = load(from: candidate) { return (group, candidate) }
        }
        return nil
    }
}
