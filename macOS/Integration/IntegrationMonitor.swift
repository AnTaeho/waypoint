import Foundation
import Observation
import WaypointKit

@MainActor @Observable
final class IntegrationMonitor {
    private(set) var history = IntegrationHistory()
    private(set) var installations: [AgentProvider: IntegrationInstallation] = [:]
    private(set) var queue = IntegrationQueue()
    private(set) var checkedAt = Date()
    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let port: UInt16
    @ObservationIgnored private var lastSessions: [AgentProvider: String] = [:]

    init(port: UInt16, home: URL = URL(fileURLWithPath: NSHomeDirectory()), directory: URL? = try? WaypointStore.supportDirectory()) {
        self.port = port; self.home = home; self.directory = directory
        if let directory {
            let url = directory.appendingPathComponent("integration-health.json")
            if FileManager.default.fileExists(atPath: url.path) {
                if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(IntegrationHistory.self, from: data) {
                    history = stored
                } else { history.issue = "진단 기록 읽기 실패" }
            }
        }
        refresh()
    }

    func refresh() {
        installations = Dictionary(uniqueKeysWithValues: AgentProvider.allCases.map {
            ($0, IntegrationInstallation.inspect(provider: $0, home: home, port: port))
        })
        if let directory { queue = IntegrationQueue.inspect(directory: directory) }
        else { queue.unreadable = true }
        checkedAt = Date()
    }

    func receive(_ provider: AgentProvider, sessionID: String, at: Date, project: String?, replayed: Bool) {
        if (history.hooks[provider.rawValue]?.at ?? .distantPast) <= at { lastSessions[provider] = sessionID }
        history.receive(provider, at: at, receivedAt: Date(), project: project, replayed: replayed)
        save()
    }

    /// 미등록 시작 폴더의 훅 이후 실제 프로젝트에 연결한 경우. 수신 시각은 바꾸지 않는다.
    func bind(sessionID: String, project: String) {
        for (provider, id) in lastSessions where id == sessionID {
            history.hooks[provider.rawValue]?.project = project
        }
        save()
    }

    func receiveMCP() { history.lastMCPAt = Date(); save() }
    func report(_ message: String) { history.issue = message; save() }
    func acknowledge() { history.issue = nil; save() }

    private func save() {
        guard let directory, let data = try? JSONEncoder().encode(history) else { return }
        do {
            let url = directory.appendingPathComponent("integration-health.json")
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        catch { history.issue = "진단 기록 저장 실패" }
    }
}
