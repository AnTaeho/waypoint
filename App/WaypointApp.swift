import SwiftData
import SwiftUI
import WaypointKit

@main
struct WaypointApp: App {
    /// 실행 인자 `-WaypointSampleData`면 샘플 저장소(Sample.store)를 쓰고 비어 있으면 시안 장면을 채운다.
    static let usesSampleData = ProcessInfo.processInfo.arguments.contains("-WaypointSampleData")

    let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.liveText)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: Theme.Size.windowWidth, height: Theme.Size.windowHeight)
        #endif
    }

    /// 저장소를 못 열면 보여 줄 것이 없고, 메모리 저장소로 넘어가면 새로 쌓인 기록을 조용히 잃는다.
    /// 개인 앱이라 원인 메시지를 남기고 멈춘다.
    private static func makeContainer() -> ModelContainer {
        do {
            if usesSampleData {
                let container = try WaypointStore.makeContainer(url: WaypointStore.sampleStoreURL())
                try SampleData.seedIfEmpty(container.mainContext)
                return container
            }
            return try WaypointStore.makeContainer(url: WaypointStore.defaultStoreURL())
        } catch {
            fatalError("Waypoint 저장소를 열 수 없음: \(error)")
        }
    }
}
