import SwiftData
import SwiftUI
import WaypointKit

struct IntegrationHealthPanel: View {
    let services: AppServices
    @Query(filter: #Predicate<Session> { $0.endedAt == nil && $0.kindRaw == "main" }) private var sessions: [Session]
    var body: some View {
        LiveDataTimeline { now in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    HStack {
                        Text("AI 연동 상태").font(Theme.sectionLarge).foregroundStyle(Theme.text)
                        Spacer()
                        Button("다시 점검") { services.retryIntegration() }.font(Theme.captionLarge)
                    }
                    serverSection
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(AppVersion.environment).font(Theme.bodyMedium)
                        Text(AppVersion.display).font(Theme.monoCaption)
                    }.foregroundStyle(Theme.textMuted).textSelection(.enabled)
                    IntegrationDiagnosticButton(services: services)
                    ForEach(AgentProvider.allCases, id: \.self) { provider in
                        IntegrationProviderStatus(provider: provider, services: services, now: now,
                            connectedProjects: Array(Set(sessions.filter { $0.provider == provider && $0.project?.archivedAt == nil }
                                .compactMap { $0.project.map { "\($0.name) (\($0.key))" } })).sorted())
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("미처리 기록 · \(services.integration.queue.count)건").font(Theme.bodyMedium)
                        Text(services.integration.queue.unreadable
                             ? "기록 폴더를 읽지 못했습니다. 폴더 권한과 저장 공간을 확인하세요."
                             : "전달에 실패한 기록은 10초마다 다시 읽습니다.")
                        if let issue = services.integration.history.issue {
                            Text(issue).foregroundStyle(Theme.liveText)
                            Button("알림 확인") { services.integration.acknowledge() }
                        }
                        if let at = services.integration.history.lastMCPAt {
                            Text("MCP 마지막 요청 · \(at.formatted(date: .abbreviated, time: .standard))")
                        } else {
                            Text("MCP 요청 없음 · AI 도구의 /mcp에서 waypoint 연결을 확인하세요.")
                        }
                    }
                    .font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
                    Text("활동이 없다는 이유만으로 연동 실패를 판단하지 않습니다. 신뢰 승인은 설정 파일만으로 확인할 수 없습니다.")
                        .font(Theme.caption).foregroundStyle(Theme.textMuted)
                    Text("마지막 점검 · \(services.integration.checkedAt.formatted(date: .omitted, time: .standard))")
                        .font(Theme.caption).foregroundStyle(Theme.textMuted)
                }
                .padding(Theme.Spacing.xl)
            }
            .frame(width: Theme.Integration.panelWidth, height: Theme.Integration.panelMaxHeight)
            .background(Theme.bg)
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(services.serverState == .ready ? "기록 수신 서버 실행 중" : "기록 수신 서버 확인 필요")
                .font(Theme.bodyMedium).foregroundStyle(services.serverState == .ready ? Theme.done : Theme.liveText)
            Text("이 앱의 연결 주소 · 127.0.0.1:\(String(services.port))")
                .font(Theme.monoCaption).foregroundStyle(Theme.textMuted)
            if services.serverState != .ready {
                Text("다른 Waypoint 인스턴스가 같은 포트를 쓰는지 확인한 뒤 앱을 다시 실행하세요.")
                    .font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
            }
        }
    }
}
