import AppKit
import SwiftData
import SwiftUI
import WaypointKit

/// 메뉴 막대 메뉴: 프로젝트별 작업중 세션 수, 기록을 받지 못할 때 한 줄, 창 열기, 종료.
struct MenuBarContent: View {
    /// 샘플 모드처럼 서버를 열지 않으면 nil
    let services: AppServices?

    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }, sort: \Project.name)
    private var projects: [Project]
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let now = Date()
        let lines = projects.compactMap { line(for: $0, now: now) }
        if lines.isEmpty {
            Text("진행 중인 작업 없음")
        } else {
            ForEach(lines, id: \.self) { Text($0) }
        }
        if case .some(.failed) = services?.serverState {
            Divider()
            Text("새 기록을 받지 못하는 중 (포트 \(String(LocalServer.defaultPort)) 사용 중)")
        }
        Divider()
        Button("Waypoint 열기") {
            openWindow(id: WaypointApp.mainWindowID)
            NSApplication.shared.activate()
        }
        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// 「가계부 앱 · 작업 2 · 멈춤 1」. 끝나지 않은 메인 세션이 없으면 nil.
    private func line(for project: Project, now: Date) -> String? {
        var live = 0, stalled = 0
        for session in project.sessions ?? [] where session.kind == .main {
            switch SessionRules.state(of: session, now: now) {
            case .live: live += 1
            case .stalled: stalled += 1
            case .ended: break
            }
        }
        guard live + stalled > 0 else { return nil }
        var parts = [project.name]
        if live > 0 { parts.append("작업 \(live)") }
        if stalled > 0 { parts.append("멈춤 \(stalled)") }
        return parts.joined(separator: " · ")
    }
}
