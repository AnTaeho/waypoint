import Foundation
import WaypointKit

/// 연동 설치·진단이 보는 홈. Debug 빌드만 `WAYPOINT_INTEGRATION_HOME`을 따른다(`IntegrationHomePolicy`).
enum IntegrationEnvironment {
    static let realHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

    #if DEBUG
    static let allowsHomeOverride = true
    #else
    static let allowsHomeOverride = false
    #endif

    static let home = IntegrationHomePolicy.home(allowOverride: allowsHomeOverride, realHome: realHome)

    /// 확인용 홈을 쓰는 중(Debug + 환경 변수)
    static var isOverridden: Bool { home != realHome }

    /// 설치·해제를 막는 까닭(Dev가 실제 홈에)
    static let installBlock = IntegrationHomePolicy.installBlock(instance: .current, home: home, realHome: realHome)

    static func context() throws -> IntegrationInstallContext? {
        try IntegrationInstallContext.current(home: home)
    }
}
