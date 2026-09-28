import SwiftData
import SwiftUI
import WaypointKit

@main
struct WaypointApp: App {
    /// 실행 인자 `-WaypointSampleData`면 메모리 저장소에 시안 장면을 채워 쓴다(파일에 남지 않는다).
    static let usesSampleData = ProcessInfo.processInfo.arguments.contains("-WaypointSampleData")

    static let mainWindowID = "main"

    let container: ModelContainer
    #if os(macOS)
    /// 로컬 서버·outbox 흡수·상태 타이머. 샘플 모드에서는 열지 않는다(메모리 저장소에 실제 기록이 섞이고 outbox를 비워 잃지 않게).
    let services: AppServices?
    /// 사용량 파일 읽기. 파일만 읽으므로 샘플 모드에서도 돈다.
    let usage = UsageMonitor()
    #endif
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    #endif

    init() {
        FontRegistry.registerBundledFonts()
        container = Self.makeContainer()
        #if os(macOS)
        services = Self.usesSampleData ? nil : AppServices(container: container)
        services?.start()
        usage.start()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            RootView()
                .tint(Theme.liveText)
                #if os(macOS)
                .environment(usage)
                .environment(services)
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: Theme.Size.windowWidth, height: Theme.Size.windowHeight)
        #endif

        #if os(macOS)
        // 메뉴 막대에 상주해 창을 닫아도 서버가 돈다.
        // 개발용은 이름·아이콘을 달리해 평소용과 함께 떠 있어도 가려 보게 한다.
        MenuBarExtra(
            AppInstance.current.isDev ? "Waypoint Dev" : "Waypoint",
            systemImage: AppInstance.current.isDev ? Theme.Dev.menuBarSymbol : "signpost.right"
        ) {
            MenuBarContent(services: services)
                .modelContainer(container)
                .environment(usage)
        }
        #endif
    }

    /// 저장소를 못 열면 보여 줄 것이 없고, 메모리 저장소로 넘어가면 새로 쌓인 기록을 조용히 잃는다.
    /// 개인 앱이라 원인 메시지를 남기고 멈춘다.
    private static func makeContainer() -> ModelContainer {
        do {
            if usesSampleData {
                // 실행할 때마다 지금 시각 기준으로 새로 채운다. 파일에 남기면 채운 시각이 굳어 15분 뒤 모두 「멈춤」이 된다.
                let container = try WaypointStore.makeContainer(inMemory: true)
                try SampleData.seedIfEmpty(container.mainContext)
                return container
            }
            return try WaypointStore.makeContainer(
                url: WaypointStore.defaultStoreURL(),
                cloudKitContainer: AppInstance.current.cloudKitContainer()
            )
        } catch {
            fatalError("Waypoint 저장소를 열 수 없음: \(error)")
        }
    }
}
