import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct AppInstanceTests {
    let base = URL(fileURLWithPath: "/Users/me/Library/Application Support", isDirectory: true)

    @Test func bundleIdentifier() {
        #expect(AppInstance(bundleIdentifier: "dev.antaeho.waypoint") == .stable)
        #expect(AppInstance(bundleIdentifier: "dev.antaeho.waypoint.dev") == .dev)
        // 명령행 도구·테스트: 번들 ID 없음 → 평소용
        #expect(AppInstance(bundleIdentifier: nil) == .stable)
        #expect(AppInstance(bundleIdentifier: "com.apple.dt.xctest.tool") == .stable)
        // 끝이 `.dev`일 때만
        #expect(AppInstance(bundleIdentifier: "dev.antaeho.waypoint.devtools") == .stable)
    }

    @Test func testsRunAsStable() {
        #expect(AppInstance.current == .stable)
    }

    @Test func defaults() {
        #expect(AppInstance.stable.defaultPort == 47821)
        #expect(AppInstance.dev.defaultPort == 47822)
        #expect(AppInstance.stable.supportFolderName == "Waypoint")
        #expect(AppInstance.dev.supportFolderName == "Waypoint-Dev")
    }

    @Test func portFromEnvironment() {
        #expect(AppInstance.dev.port(environment: [:]) == 47822)
        #expect(AppInstance.stable.port(environment: ["WAYPOINT_PORT": "47999"]) == 47999)
        #expect(AppInstance.dev.port(environment: ["WAYPOINT_PORT": " 48000 "]) == 48000)
        // 잘못된 값은 무시하고 기본값
        for bad in ["", "0", "-1", "65536", "abc", "4782x"] {
            #expect(AppInstance.dev.port(environment: ["WAYPOINT_PORT": bad]) == 47822, "\(bad)")
        }
    }

    @Test func supportDirectory() {
        #expect(AppInstance.stable.supportDirectory(base: base, environment: [:]).path
            == "/Users/me/Library/Application Support/Waypoint")
        #expect(AppInstance.dev.supportDirectory(base: base, environment: [:]).path
            == "/Users/me/Library/Application Support/Waypoint-Dev")
        // 환경 변수가 먼저, `~`는 펼친다
        #expect(AppInstance.dev.supportDirectory(base: base, environment: ["WAYPOINT_SUPPORT_DIR": "/tmp/wp"]).path
            == "/tmp/wp")
        #expect(AppInstance.stable.supportDirectory(base: base, environment: ["WAYPOINT_SUPPORT_DIR": "~/x"]).path
            == NSHomeDirectory() + "/x")
        // 빈 값은 없는 것과 같다
        #expect(AppInstance.dev.supportDirectory(base: base, environment: ["WAYPOINT_SUPPORT_DIR": ""]).lastPathComponent
            == "Waypoint-Dev")
    }

    @Test func cloudKitContainer() {
        #expect(AppInstance.stable.cloudKitContainer(environment: [:]) == "iCloud.dev.antaeho.waypoint")
        #expect(AppInstance.dev.cloudKitContainer(environment: [:]) == "iCloud.dev.antaeho.waypoint.dev")
        // 끄는 스위치
        #expect(AppInstance.stable.cloudKitContainer(environment: ["WAYPOINT_CLOUDKIT": "0"]) == nil)
        #expect(AppInstance.dev.cloudKitContainer(environment: ["WAYPOINT_CLOUDKIT": " 0 "]) == nil)
        // 0이 아닌 값은 켠 채로
        for on in ["", "1", "yes"] {
            #expect(AppInstance.dev.cloudKitContainer(environment: ["WAYPOINT_CLOUDKIT": on]) != nil, "\(on)")
        }
        // 저장 폴더를 옮기면 끈다(빈 값은 없는 것과 같다)
        #expect(AppInstance.stable.cloudKitContainer(environment: ["WAYPOINT_SUPPORT_DIR": "/tmp/wp"]) == nil)
        #expect(AppInstance.stable.cloudKitContainer(environment: ["WAYPOINT_SUPPORT_DIR": ""]) != nil)
    }

    @Test func cloudKitDatabase() {
        func identifier(_ container: String?) -> String? {
            ModelConfiguration(
                schema: WaypointStore.schema, isStoredInMemoryOnly: true,
                cloudKitDatabase: WaypointStore.cloudKitDatabase(container)
            ).cloudKitContainerIdentifier
        }
        #expect(identifier(nil) == nil)
        #expect(identifier("") == nil)
        #expect(identifier("iCloud.x") == "iCloud.x")
    }
}
