import Foundation
import ServiceManagement
import WaypointKit

/// `SMAppService.mainApp`(macOS 13+)로 이 앱을 로그인 항목에 등록·해제한다(TRK-55).
/// System Events·Apple Events는 쓰지 않는다. 옛 방식 항목은 `scripts/install-local.sh`가 지운다.
@MainActor
final class SystemLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }

    /// 시스템 설정 > 일반 > 로그인 항목
    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

extension LoginItemController {
    /// 지금 앱용. Dev는 실제 서비스를 만들지 않는다(상태도 읽지 않는다).
    static func forCurrentApp() -> LoginItemController {
        let isDev = AppInstance.current.isDev
        let service: LoginItemService = isDev ? DisabledLoginItemService() : SystemLoginItemService()
        return LoginItemController(service: service, store: UserDefaults.standard, isDev: isDev)
    }

    /// 서비스 없이 그리는 샘플 화면용(꺼짐·비활성)
    static func disabled() -> LoginItemController {
        LoginItemController(service: DisabledLoginItemService(), store: UserDefaults.standard, isDev: true)
    }
}
