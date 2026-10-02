import AppKit
import SwiftUI
import WaypointKit

struct IntegrationDiagnosticButton: View {
    let services: AppServices
    @State private var copiedAt: Date?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button("진단 정보 복사", systemImage: "doc.on.doc", action: copy)
                .font(Theme.captionLarge)
            if failed {
                Text("복사 실패")
                    .foregroundStyle(Theme.liveText)
            } else if let copiedAt {
                Text("\(copiedAt.formatted(date: .omitted, time: .standard)) 기준 복사됨")
                    .foregroundStyle(Theme.done)
            }
        }.font(Theme.caption)
    }

    private func copy() {
        let monitor = services.integration
        let report = IntegrationDiagnostic.text(
            version: AppVersion.display, environment: AppVersion.environment,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            port: services.port, serverReady: services.serverState == .ready,
            history: monitor.history, installations: monitor.installations,
            queue: monitor.queue, checkedAt: monitor.checkedAt, metrics: services.reliability.metrics,
            coverage: services.trackingCoverage())
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(report, forType: .string)
        copiedAt = success ? Date() : nil
        failed = !success
    }
}
