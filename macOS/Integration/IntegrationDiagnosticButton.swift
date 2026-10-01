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
                Text("클립보드에 복사하지 못했습니다. 다시 시도해 주세요.")
                    .foregroundStyle(Theme.liveText)
            } else if let copiedAt {
                Text("\(copiedAt.formatted(date: .omitted, time: .standard)) 기준 복사됨")
                    .foregroundStyle(Theme.done)
            }
            Text("버전·연동 상태·수신 시각만 복사합니다. 프로젝트명과 대화 내용은 포함하지 않습니다.")
                .foregroundStyle(Theme.textMuted)
        }.font(Theme.caption)
    }

    private func copy() {
        let monitor = services.integration
        let report = IntegrationDiagnostic.text(
            version: AppVersion.display, environment: AppVersion.environment,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            port: services.port, serverReady: services.serverState == .ready,
            history: monitor.history, installations: monitor.installations,
            queue: monitor.queue, checkedAt: monitor.checkedAt)
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(report, forType: .string)
        copiedAt = success ? Date() : nil
        failed = !success
    }
}
