import Foundation

public enum AppVersion {
    public static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "알 수 없음"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "알 수 없음"
        return "\(version) · 빌드 \(build)"
    }

    public static var environment: String {
        AppInstance.current.isDev ? "Waypoint Dev · 개발용" : "Waypoint · 일반용"
    }
}
