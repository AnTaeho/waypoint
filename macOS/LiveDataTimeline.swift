import SwiftData
import SwiftUI

/// 저장·훅 수신은 즉시 반영하고, 시간만 흐르는 상태도 5초마다 다시 계산한다.
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
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            refreshedAt = Date()
        }
    }

    private static var interval: TimeInterval { 5 }
}
