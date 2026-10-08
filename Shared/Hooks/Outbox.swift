import Foundation
import SwiftData

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
        /// 시간 예산(`deadline`)이 다 돼 남은 줄을 두고 멈췄다. 곧 이어서 처리한다(원격 replay, TRK-53).
        public var more = false
    }

    /// 한 줄의 저장 실패. `drain`의 `handle`이 던져 그 줄부터 남기게 한다.
    public struct SaveFailed: Error {
        public init() {}
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
    /// `deadline`이 있으면 한 줄 이상 처리한 뒤 그 시각이 지나면 남은 줄을 떼어 낸 파일에 다시 쓰고 멈춘다(`more`).
    /// 다음 drain이 그 줄부터 이어 간다(순서 유지). 원격 replay가 메인 액터를 오래 잡지 않게 한다(`RemoteReplay`, TRK-53).
    @discardableResult
    public static func drain(
        directory: URL,
        fileManager: FileManager = .default,
        deadline: Date? = nil,
        handle: (Entry) throws -> Void
    ) -> DrainResult {
        var result = DrainResult()
        let outbox = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: outbox.path) {
            // 남아 있는 처리 중 파일 모두보다 뒤에 정렬되는 이름을 짓는다(같은 밀리초에 다시 흡수해도 순서 유지)
            let latest = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasPrefix(processingPrefix) && $0.hasSuffix(".jsonl") }
                .compactMap { Int($0.dropFirst(processingPrefix.count).prefix { ("0"..."9").contains($0) }) }
                .max() ?? -1
            let stamp = max(Int(Date().timeIntervalSince1970 * 1000), min(latest, Int.max - 1) + 1)
            let padded = String(repeating: "0", count: max(0, 13 - String(stamp).count)) + String(stamp)
            let claimed = directory.appendingPathComponent("\(processingPrefix)\(padded)-\(UUID().uuidString).jsonl")
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
                if let deadline, result.processed + result.skipped > 0, Date() >= deadline {
                    var paused = preserve(lines[index...], at: url, result: result)
                    paused.retryPending = result.retryPending
                    paused.more = true
                    return paused
                }
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

    // MARK: - 원격 replay (TRK-53)

    /// `POST /hooks/replay` 한 번에 받는 최대 줄 수. 훅 스크립트는 100줄씩 보낸다.
    public static let replayLineLimit = 500

    public struct AppendResult: Equatable, Sendable {
        public var accepted = 0
        /// 읽을 수 없어 받지 않은 줄
        public var rejected = 0
    }

    /// outbox 줄(JSON Lines)을 `directory`의 outbox 끝에 붙인다(원격 replay는 `RemoteReplay.directory`).
    /// 읽을 수 있는 줄(`parse`)만 붙이고 나머지는 센다. 한 번의 쓰기(O_APPEND)로 붙여 훅 스크립트가 같은 파일에
    /// 쓰는 줄과 섞이지 않는다. 쓰지 못하면 오류(호출 쪽은 5xx로 답해 원격이 줄을 지우지 않게 한다).
    public static func append(_ body: Data, directory: URL, fileManager: FileManager = .default) throws -> AppendResult {
        var result = AppendResult()
        var accepted = Data()
        let text = String(decoding: body, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard parse(line: Substring(trimmed)) != nil else {
                result.rejected += 1
                continue
            }
            accepted.append(Data((trimmed + "\n").utf8))
            result.accepted += 1
        }
        guard !accepted.isEmpty else { return result }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(fileName).path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw SaveFailed() }
        defer { close(fd) }
        let written = accepted.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == accepted.count else { throw SaveFailed() }
        return result
    }

    /// 실시간 훅 하나를 outbox 한 줄로(끝 줄바꿈 포함). 본문이 JSON 객체가 아니면 nil.
    /// 원격 replay가 남은 동안 블록이 필요 없는 실시간 훅을 그 뒤에 세워 순서를 지킨다(`AppServices`, TRK-53).
    public static func line(event: String, provider: AgentProvider, receivedAt: Date, pid: Int?, payload body: Data) -> Data? {
        guard let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        var object: [String: Any] = ["event": event, "receivedAt": receivedAt.timeIntervalSince1970, "payload": payload]
        if provider != .claude { object["provider"] = provider.rawValue }
        if let pid { object[provider == .claude ? "claudePid" : "processPid"] = pid }
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        data.append(UInt8(ascii: "\n"))
        return data
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
    /// outbox를 흡수 한 번마다 새 `ModelContext`(같은 컨테이너)에서 처리한다(SPEC 6장, DECISIONS 2026-10-01 TRK-33).
    ///
    /// 줄마다 저장하고, 저장에 실패하면 그 줄부터 남기고(`Outbox.drain`) 흡수용 context를 통째로 버린다.
    /// rollback이 되돌리지 못한 메모리 값이 이 처리기의 context(앱의 메인 context)에 들어오지 않으므로 같은 실행에서
    /// 바로 다시 흡수해도 된다. 흡수 뒤 이 context가 올려 둔 객체를 저장소 값으로 맞춘다(`ContextReload`).
    /// 먼저 이 context의 저장 안 된 변경을 저장한다. 저장하지 못하면 흡수하지 않고 `retryPending`을 돌려준다
    /// (저장 안 된 객체는 다시 읽어도 바뀌지 않고, 나중에 저장하면 흡수한 값을 덮는다).
    /// 서브에이전트 대기 항목(`pendingSpawns`)은 흡수용 처리기에 넘겼다가 저장된 결과대로 돌려받는다.
    /// `received`는 저장에 성공한 줄마다 부른다.
    @discardableResult
    public func absorbOutbox(
        directory: URL,
        fileManager: FileManager = .default,
        received: (Outbox.Entry) -> Void = { _ in }
    ) -> Outbox.DrainResult {
        if context.hasChanges {
            do { try saveContext(context) } catch {}
            guard !context.hasChanges else { return Outbox.DrainResult(retryPending: true) }
        }
        let scratch = ModelContext(context.container)
        scratch.autosaveEnabled = false
        let worker = HookProcessor(context: scratch, stallTimeout: stallTimeout, home: home, gitBranch: gitBranch)
        worker.saveContext = saveContext
        worker.localOrigin = localOrigin
        worker.pathExists = pathExists
        worker.pendingSpawns = pendingSpawns
        worker.seenSpawns = seenSpawns
        let result = Outbox.drain(directory: directory, fileManager: fileManager) { entry in
            worker.handle(entry)
            guard !worker.lastSaveFailed else { throw Outbox.SaveFailed() }
            received(entry)
        }
        pendingSpawns = worker.pendingSpawns
        seenSpawns = worker.seenSpawns
        if result.processed > 0 || result.retryPending { ContextReload.apply(context) }
        return result
    }

    /// outbox 한 줄을 처리한다. 시각은 훅이 받은 시각(`receivedAt`).
    /// 이미 지난 훅이라 대화에 넣을 수 없으므로 주입 텍스트를 만들지 않고, 블록을 줬다고 적지도 않는다.
    public func handle(_ entry: Outbox.Entry) {
        handle(event: entry.event, json: entry.payload, at: entry.receivedAt,
               claudePid: entry.claudePid, delivers: false, provider: entry.provider, processPid: entry.processPid)
    }
}
