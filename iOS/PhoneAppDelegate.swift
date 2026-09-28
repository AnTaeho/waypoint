import UIKit

/// 원격 알림 등록. CloudKit 미러링은 iOS에서 스스로 등록하지 않아(2026-09 실측: 등록 없이는 Mac 변경이
/// 앱을 다시 열 때까지 오지 않았다) 여기서 등록한다. 알림 처리는 미러링이 한다.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    #if DEBUG
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PhoneDebugLog.print("push registered")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PhoneDebugLog.print("push register failed \(error)")
    }

    func application(
        _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        PhoneDebugLog.print("push received state=\(application.applicationState.rawValue)")
        return .noData
    }
    #endif
}
