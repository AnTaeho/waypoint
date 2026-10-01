import Foundation

/// 로컬 진단 정보. 대화·프롬프트·파일 경로는 저장하지 않는다.
public struct IntegrationReceipt: Codable, Equatable, Sendable {
    public var at: Date
    public var receivedAt: Date
    public var project: String?
    public var replayed: Bool
    public init(at: Date, receivedAt: Date, project: String?, replayed: Bool) {
        self.at = at; self.receivedAt = receivedAt; self.project = project; self.replayed = replayed
    }
}

public struct IntegrationHistory: Codable, Equatable, Sendable {
    public var hooks: [String: IntegrationReceipt] = [:]
    public var lastMCPAt: Date?
    public var issue: String?
    public init() {}

    /// 늦게 재전송된 기록이 최신 정보를 되돌리지 않도록 원래 활동 시각으로 비교한다.
    public mutating func receive(_ provider: AgentProvider, at: Date, receivedAt: Date,
                                 project: String?, replayed: Bool) {
        if let previous = hooks[provider.rawValue], previous.at > at { return }
        hooks[provider.rawValue] = IntegrationReceipt(at: at, receivedAt: receivedAt,
                                                      project: project, replayed: replayed)
    }
}

public enum IntegrationState: Equatable, Sendable {
    case attention, setup, waiting, received
    public var title: String {
        switch self {
        case .attention: "확인 필요"
        case .setup: "설정 필요"
        case .waiting: "첫 수신 대기"
        case .received: "수신 확인"
        }
    }
    public static func evaluate(serverReady: Bool, installation: IntegrationInstallation,
                                receipt: IntegrationReceipt?, pending: Int, issue: String?) -> Self {
        if !serverReady || pending > 0 || issue != nil || installation.state == .attention { return .attention }
        if let receipt { return receipt.project == nil ? .attention : .received }
        return installation.state == .missing ? .setup : .waiting
    }
}

public struct IntegrationQueue: Equatable, Sendable {
    public var count = 0
    public var unreadable = false
    public init() {}
    public static func inspect(directory: URL) -> Self {
        var result = Self()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            result.unreadable = FileManager.default.fileExists(atPath: directory.path)
            return result
        }
        for name in names where name == Outbox.fileName || (name.hasPrefix("outbox.processing-") && name.hasSuffix(".jsonl")) {
            guard let data = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else {
                result.unreadable = true; continue
            }
            result.count += data.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        }
        return result
    }
}
