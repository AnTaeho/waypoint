import AppKit
import SwiftData
import SwiftUI
import WaypointKit

/// 손 없이 대시보드를 확인할 때의 Debug 전용 실행 인자(TRK-64). Release에서는 아무것도 하지 않는다.
/// - `-WaypointWindowSize 1400x900`: 메인 창 크기를 바꾼다(창을 앞으로 가져오지 않는다).
/// - `-WaypointDashboardScroll board`: 대시보드를 상황판까지 내린다.
/// - `-WaypointOpenCard PRB-1`: 그 카드 상세(와 카드 인스펙터)를 연다(TRK-17).
extension View {
    func cardLaunch(_ path: Binding<[Card]>) -> some View {
        modifier(CardLaunch(path: path))
    }

    func dashboardScrollLaunch(_ reader: ScrollViewProxy) -> some View {
        modifier(DashboardScrollLaunch(reader: reader))
    }

    func windowSizeLaunch() -> some View {
        modifier(WindowSizeLaunch())
    }
}

private struct DashboardScrollLaunch: ViewModifier {
    let reader: ScrollViewProxy

    func body(content: Content) -> some View {
        content.task {
            #if DEBUG
            guard UserDefaults.standard.string(forKey: "WaypointDashboardScroll") == "board" else { return }
            try? await Task.sleep(for: .milliseconds(800))
            reader.scrollTo(SituationBoard.scrollID, anchor: .top)
            #endif
        }
    }
}

private struct WindowSizeLaunch: ViewModifier {
    @MainActor private static var applied = false

    func body(content: Content) -> some View {
        content.task {
            #if DEBUG
            guard !Self.applied, let raw = UserDefaults.standard.string(forKey: "WaypointWindowSize") else { return }
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return }
            Self.applied = true
            try? await Task.sleep(for: .milliseconds(300))
            // 메뉴 막대·설정 창을 빼고 가장 큰 제목 있는 창이 메인 창이다(숨긴 채 띄우면 canBecomeMain이 거짓일 수 있다).
            guard let window = NSApp.windows.filter({ $0.styleMask.contains(.titled) })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            else { NSLog("Waypoint 창 크기: 창 없음"); return }
            var frame = window.frame
            frame.origin.y += frame.height - parts[1]
            frame.size = CGSize(width: parts[0], height: parts[1])
            window.setFrame(frame, display: true)
            NSLog("Waypoint 창 크기 \(Int(window.frame.width))x\(Int(window.frame.height)) 번호 \(window.windowNumber)")
            #endif
        }
    }
}

private struct CardLaunch: ViewModifier {
    @Binding var path: [Card]
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.task {
            #if DEBUG
            guard path.isEmpty, let raw = UserDefaults.standard.string(forKey: "WaypointOpenCard") else { return }
            let parts = raw.split(separator: "-")
            guard parts.count == 2, let number = Int(parts[1]) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            guard let card = projects.first(where: { $0.key == String(parts[0]) })?.cards?
                .first(where: { $0.number == number }) else { NSLog("Waypoint 카드 열기: 없음 \(raw)"); return }
            path = [card]
            #endif
        }
    }
}
