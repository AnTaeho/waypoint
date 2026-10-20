import SwiftUI

/// 저장·훅 수신(`AppServices.lastDataChange`, 묶어서 0.5초 안)과 5초마다 다시 계산한다.
struct LiveDataTimeline<Content: View>: View {
    @Environment(AppServices.self) private var services: AppServices?
    @State private var refreshedAt = Date()
    let content: (Date) -> Content

    init(@ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.interval)) { timeline in
            content(max(timeline.date, refreshedAt))
        }
        .onChange(of: services?.lastDataChange) { _, date in
            if let date { refreshedAt = date }
        }
    }

    private static var interval: TimeInterval { 5 }
}
