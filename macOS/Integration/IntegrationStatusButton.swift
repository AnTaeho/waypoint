import SwiftUI
import WaypointKit

/// 대시보드·프로젝트 보드 어느 화면에서도 연동 상태를 확인한다.
struct IntegrationStatusButton: View {
    @Environment(AppServices.self) private var services: AppServices?
    @State private var showsDetails = false
    var compact = true

    var body: some View {
        if let services {
            let warning = states(services).contains(.attention)
            Group {
                if compact {
                    // 툴바가 아이콘 크기·클릭 영역·배경 여백을 함께 결정한다.
                    Button { showsDetails.toggle(); services.refreshStates() } label: {
                        Label(warning ? "연동 확인 필요" : "연동 상태",
                              systemImage: symbol(warning))
                    }
                } else {
                    Button { showsDetails.toggle(); services.refreshStates() } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: symbol(warning))
                            Text("AI 연동")
                            ForEach(AgentProvider.allCases, id: \.self) { provider in
                                Text("\(provider.name) · \(state(provider, services).title)")
                                    .font(Theme.captionLarge)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(Theme.Spacing.l)
                        .background(Theme.bgPanel, in: RoundedRectangle(cornerRadius: Theme.Integration.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .font(Theme.body)
                }
            }
            .foregroundStyle(warning ? Theme.liveText : Theme.textMuted)
            .help("Claude·Codex의 설정, 마지막 수신과 누락 기록 확인")
            .popover(isPresented: $showsDetails) { IntegrationHealthPanel(services: services) }
        }
    }

    private func symbol(_ warning: Bool) -> String {
        warning ? "exclamationmark.circle" : "antenna.radiowaves.left.and.right"
    }

    private func states(_ services: AppServices) -> [IntegrationState] {
        AgentProvider.allCases.map { state($0, services) }
    }
    private func state(_ provider: AgentProvider, _ services: AppServices) -> IntegrationState {
        IntegrationState.evaluate(serverReady: services.serverState == .ready,
            installation: services.integration.installations[provider] ?? .init(state: .missing, detail: ""),
            receipt: services.integration.history.hooks[provider.rawValue], pending: services.integration.queue.count,
            issue: services.integration.queue.unreadable ? "읽기 실패" : services.integration.history.issue)
    }
}
