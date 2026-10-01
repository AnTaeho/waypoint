import Foundation

/// 앱이 꺼져 있는 동안 훅 스크립트가 쌓은 `outbox.jsonl` 흡수(SPEC 6장).
/// 한 줄: `{"event":"<EventName>","receivedAt":<unix>,"claudePid":<PID, 없을 수 있음>,"trimmed":true,"payload":<앱이 읽는 필드만 남긴 JSON>}`
public enum Outbox {

    public static let fileName = "outbox.jsonl"
    /// 흡수 중 파일 이름 앞부분. 흡수하다 앱이 죽으면 다음 실행에서 이어 처리한다.
    static let processingPrefix = "outbox.processing-"
    /// 읽을 수 없는 줄을 원문 그대로 옮겨 두는 파일. 흡수·재시도 대상이 아니고 미처리 기록 수에 들지 않는다.
    public static let quarantineFileName = "outbox.quarantine.jsonl"

    public struct Entry {
        public let provider: AgentProvider
        public let event: String
        public let receivedAt: Date
        public let payload: Data
        /// 훅을 부른 Claude Code 프로세스 PID(스크립트가 찾았을 때만)
        public let claudePid: Int?
        public let processPid: Int?
    }

    public struct DrainResult: Equatable, Sendable {
        public var processed = 0
        /// 읽을 수 없어 격리 파일(`quarantineFileName`)로 옮긴 줄
        public var skipped = 0
        /// 처리 실패로 원본을 보존했다. 다음 점검에서 이 줄부터 다시 시도한다.
        public var retryPending = false
    }

    /// 한 줄을 읽는다. 형식이 틀리면 nil.
    public static func parse(line: Substring) -> Entry? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String, !event.isEmpty,
              let receivedAt = (object["receivedAt"] as? NSNumber)?.doubleValue,
              let payload = object["payload"] as? [String: Any],
              let payloadData = try? JSONSerialization.data(withJSONObject: payload)
        else { return nil }
        let provider: AgentProvider
        if let raw = object["provider"] as? String {
            guard let known = AgentProvider(rawValue: raw) else { return nil }
            provider = known
        } else {
            provider = .claude
        }
        return Entry(provider: provider, event: event, receivedAt: Date(timeIntervalSince1970: receivedAt), payload: payloadData,
                     claudePid: HookParsing.pid(object["claudePid"]), processPid: HookParsing.pid(object["processPid"]))
    }

    /// `directory`의 outbox를 처리하고 비운다.
    /// 먼저 파일 이름을 바꿔 떼어 낸 뒤(그사이 훅이 쓰는 줄은 새 outbox로 간다) 줄 순서대로 `handle`을 부르고, 떼어 낸 파일을 지운다.
    /// 지난번에 떼어 낸 채 남은 파일이 있으면 그것부터 처리한다.
    /// 읽을 수 없는 줄은 원문 그대로 격리 파일에 덧붙인다.
    /// handle이 실패하면(또는 격리 파일에 쓰지 못하면) 해당 줄과 이후 줄을 보존하고 모든 파일의 처리를 중단한다.
    /// 다음 drain이 그 줄부터 다시 시도한다. 횟수 제한은 없다(DECISIONS 2026-10-01).
    /// 남은 줄 저장마저 실패하면 원본 전체를 유지한다(기록 손실보다 재수신을 우선).
    @discardableResult
    public static func drain(
        directory: URL,
        fileManager: FileManager = .default,
        handle: (Entry) throws -> Void
    ) -> DrainResult {
        var result = DrainResult()
        let outbox = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: outbox.path) {
            let claimed = directory.appendingPathComponent("\(processingPrefix)\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).jsonl")
            try? fileManager.moveItem(at: outbox, to: claimed)
        }
        let pending = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix(processingPrefix) && $0.hasSuffix(".jsonl") }
            .sorted()
        for name in pending {
            let url = directory.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            for (index, line) in lines.enumerated() {
                if let entry = parse(line: line) {
                    do {
                        try handle(entry)
                    } catch {
                        return preserve(lines[index...], at: url, result: result)
                    }
                    result.processed += 1
                } else {
                    guard quarantine(line, in: directory, fileManager: fileManager) else {
                        return preserve(lines[index...], at: url, result: result)
                    }
                    result.skipped += 1
                }
            }
            try? fileManager.removeItem(at: url)
        }
        return result
    }

    /// 처리하지 못한 줄부터 끝까지를 떼어 낸 파일에 다시 쓴다. 쓰지 못하면 파일을 그대로 둔다.
    private static func preserve(_ remaining: ArraySlice<Substring>, at url: URL, result: DrainResult) -> DrainResult {
        var result = result
        result.retryPending = true
        try? (remaining.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return result
    }

    /// 읽을 수 없는 줄을 격리 파일 끝에 덧붙인다(소유자만 읽기·쓰기). 실패하면 false.
    private static func quarantine(_ line: Substring, in directory: URL, fileManager: FileManager) -> Bool {
        let url = directory.appendingPathComponent(quarantineFileName)
        let data = Data((line + "\n").utf8)
        guard fileManager.fileExists(atPath: url.path) else {
            return fileManager.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? file.close() }
        do {
            try file.seekToEnd()
            try file.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }
}

extension HookProcessor {
    /// outbox 한 줄을 처리한다. 시각은 훅이 받은 시각(`receivedAt`).
    /// 이미 지난 훅이라 대화에 넣을 수 없으므로 주입 텍스트를 만들지 않고, 블록을 줬다고 적지도 않는다.
    public func handle(_ entry: Outbox.Entry) {
        handle(event: entry.event, json: entry.payload, at: entry.receivedAt,
               claudePid: entry.claudePid, delivers: false, provider: entry.provider, processPid: entry.processPid)
    }
}
