import SwiftUI
import WaypointKit

struct IntegrationProviderStatus: View {
    let provider: AgentProvider
    let services: AppServices
    let now: Date
    let connectedProjects: [String]
    var body: some View {
        let monitor = services.integration
        let installation = monitor.installations[provider] ?? .init(state: .missing, detail: "설정 확인 중")
        let receipt = monitor.history.hooks[provider.rawValue]
        let state = IntegrationState.evaluate(serverReady: services.serverState == .ready, installation: installation,
            receipt: receipt, pending: monitor.queue.count, issue: monitor.queue.unreadable ? "읽기 실패" : monitor.history.issue)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text(provider.name).font(Theme.bodyMedium).foregroundStyle(Theme.text)
                Spacer()
                Text(state.title).font(Theme.captionLargeMedium)
                    .foregroundStyle(state == .attention ? Theme.liveText : state == .received ? Theme.done : Theme.textMuted)
            }
            Text(installation.detail).font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
            Text(connectedProjects.isEmpty ? "현재 연결된 프로젝트 없음" : "현재 연결 · " + connectedProjects.joined(separator: ", "))
            if let receipt {
                Text("마지막 수신 · \(receipt.at.formatted(date: .abbreviated, time: .standard))")
                if receipt.replayed {
                    Text("누락 기록 재수신 · \(receipt.receivedAt.formatted(date: .abbreviated, time: .standard))")
                } else {
                    Text("\(max(0, Int(now.timeIntervalSince(receipt.receivedAt) / 60)))분 전 수신")
                }
                Text(receipt.project.map { "프로젝트 · \($0)" } ?? "프로젝트 미연결")
                    .foregroundStyle(receipt.project == nil ? Theme.liveText : Theme.textMuted)
            } else {
                Text("수신 기록 없음")
            }
        }
        .font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Integration.cornerRadius))
    }
}
