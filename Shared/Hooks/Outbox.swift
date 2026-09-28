import Foundation

/// 앱이 꺼져 있는 동안 훅 스크립트가 쌓은 `outbox.jsonl` 흡수(SPEC 6장).
/// 한 줄: `{"event":"<EventName>","receivedAt":<unix>,"claudePid":<PID, 없을 수 있음>,"payload":<원본 JSON>}`
public enum Outbox {

    public static let fileName = "outbox.jsonl"
    /// 흡수 중 파일 이름 앞부분. 흡수하다 앱이 죽으면 다음 실행에서 이어 처리한다.
    static let processingPrefix = "outbox.processing-"

    public struct Entry {
        public let event: String
        public let receivedAt: Date
        public let payload: Data
        /// 훅을 부른 Claude Code 프로세스 PID(스크립트가 찾았을 때만)
        public let claudePid: Int?
    }

    public struct DrainResult: Equatable, Sendable {
        public var processed = 0
        /// 읽을 수 없어 버린 줄
        public var skipped = 0
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
        return Entry(event: event, receivedAt: Date(timeIntervalSince1970: receivedAt), payload: payloadData,
                     claudePid: HookParsing.pid(object["claudePid"]))
    }

    /// `directory`의 outbox를 처리하고 비운다.
    /// 먼저 파일 이름을 바꿔 떼어 낸 뒤(그사이 훅이 쓰는 줄은 새 outbox로 간다) 줄 순서대로 `handle`을 부르고, 떼어 낸 파일을 지운다.
    /// 지난번에 떼어 낸 채 남은 파일이 있으면 그것부터 처리한다.
    @discardableResult
    public static func drain(
        directory: URL,
        fileManager: FileManager = .default,
        handle: (Entry) -> Void
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
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let entry = parse(line: line) {
                    handle(entry)
                    result.processed += 1
                } else {
                    result.skipped += 1
                }
            }
            try? fileManager.removeItem(at: url)
        }
        return result
    }
}

extension HookProcessor {
    /// outbox 한 줄을 처리한다. 시각은 훅이 받은 시각(`receivedAt`). SessionStart의 주입 텍스트는 버린다.
    public func handle(_ entry: Outbox.Entry) {
        handle(event: entry.event, json: entry.payload, at: entry.receivedAt, claudePid: entry.claudePid)
    }
}
