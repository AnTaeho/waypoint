import Foundation
import Testing
@testable import WaypointKit

@Suite struct IntegrationHealthTests {
    @Test func installationIsNotProofOfReceiptAndIdleIsNotFailure() {
        let setup = IntegrationInstallation(state: .ready, detail: "")
        #expect(IntegrationState.evaluate(serverReady: true, installation: setup, receipt: nil, pending: 0, issue: nil) == .waiting)
        let old = IntegrationReceipt(at: t0, receivedAt: t0, project: "TRK", replayed: false)
        #expect(IntegrationState.evaluate(serverReady: true, installation: setup, receipt: old, pending: 0, issue: nil) == .received)
        #expect(IntegrationState.evaluate(serverReady: false, installation: setup, receipt: old, pending: 0, issue: nil) == .attention)
        #expect(IntegrationState.evaluate(serverReady: true, installation: setup, receipt: old, pending: 1, issue: nil) == .attention)
        #expect(IntegrationState.evaluate(serverReady: true, installation: setup, receipt: old, pending: 0, issue: "failed") == .attention)
        let unbound = IntegrationReceipt(at: t0, receivedAt: t0, project: nil, replayed: false)
        #expect(IntegrationState.evaluate(serverReady: true, installation: setup, receipt: unbound, pending: 0, issue: nil) == .attention)
        // 프로젝트별 훅으로 수신했다면 사용자 범위 설정이 없어도 미설치로 단정하지 않는다.
        #expect(IntegrationState.evaluate(serverReady: true, installation: .init(state: .missing, detail: ""), receipt: old, pending: 0, issue: nil) == .received)
    }

    @Test func delayedReplayCannotReplaceLatestReceiptAndHistoryPersists() throws {
        var history = IntegrationHistory()
        history.receive(.codex, at: t0 + 60, receivedAt: t0 + 60, project: "TRK", replayed: false)
        history.receive(.codex, at: t0, receivedAt: t0 + 120, project: nil, replayed: true)
        #expect(history.hooks["codex"]?.project == "TRK")
        history.receive(.claude, at: t0, receivedAt: t0 + 120, project: "CHM", replayed: true)
        let decoded = try JSONDecoder().decode(IntegrationHistory.self, from: JSONEncoder().encode(history))
        #expect(decoded == history && decoded.hooks["claude"]?.replayed == true)
    }

    @Test func queueIncludesClaimedFilesAndMalformedLinesWithoutCountingLogs() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "{}\ninvalid\n\n".write(to: dir.appendingPathComponent("outbox.jsonl"), atomically: true, encoding: .utf8)
        try "{}\n".write(to: dir.appendingPathComponent("outbox.processing-123.jsonl"), atomically: true, encoding: .utf8)
        try "ignored".write(to: dir.appendingPathComponent("integration-health.json"), atomically: true, encoding: .utf8)
        #expect(IntegrationQueue.inspect(directory: dir).count == 3)
    }

    @Test func configurationDetectsMissingPartialDisabledAndWrongPort() throws {
        let dir = try temporary()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(IntegrationInstallation.inspect(provider: .codex, home: dir, port: 47821).state == .missing)
        let config = dir.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bridge = dir.appendingPathComponent(".codex/waypoint/waypoint-codex-hook.sh")
        try FileManager.default.createDirectory(at: bridge.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/bash".write(to: bridge, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bridge.path)
        try "test".write(to: bridge.deletingLastPathComponent().appendingPathComponent("waypoint-hook.sh"), atomically: true, encoding: .utf8)
        let group: [[String: Any]] = [["hooks": [["type": "command", "command": "WAYPOINT_PORT=47821 waypoint-codex-hook.sh Stop"]]]]
        var hooks = Dictionary(uniqueKeysWithValues: IntegrationInstallation.events.map { ($0, group) })
        func write(disabled: Bool = false) throws {
            try JSONSerialization.data(withJSONObject: ["hooks": hooks, "disableAllHooks": disabled]).write(to: config)
        }
        try write()
        #expect(IntegrationInstallation.inspect(provider: .codex, home: dir, port: 47821).state == .ready)
        #expect(IntegrationInstallation.inspect(provider: .codex, home: dir, port: 47822).state == .attention)
        try write(disabled: true)
        #expect(IntegrationInstallation.inspect(provider: .codex, home: dir, port: 47821).state == .attention)
        hooks.removeValue(forKey: "SessionEnd"); try write()
        #expect(IntegrationInstallation.inspect(provider: .codex, home: dir, port: 47821).detail.contains("SessionEnd"))
        #expect(IntegrationInstallation.hooksDisabled("[features]\nhooks = false # off\n"))
        #expect(IntegrationInstallation.hooksDisabled("features.hooks = false\n"))
        #expect(!IntegrationInstallation.hooksDisabled("[other]\nhooks = false\n[features]\nhooks = true\n"))
        #expect(!IntegrationInstallation.hooksDisabled("[other]\nfeatures.hooks = false\n"))
    }

    private func temporary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
