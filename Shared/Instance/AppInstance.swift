import Foundation

/// 평소용(Stable)과 개발용(Dev) 인스턴스. 번들 ID로 가르고, 포트·저장 폴더 기본값을 여기서 정한다.
/// 둘이 동시에 떠 있어도 서버·저장소가 겹치지 않게 한다. 환경 변수가 있으면 그 값이 먼저다.
public enum AppInstance: Sendable, Equatable {
    case stable
    case dev

    /// Debug 구성의 번들 ID는 `dev.antaeho.waypoint.dev`.
    public static let devBundleSuffix = ".dev"
    /// 포트를 바꾸는 환경 변수. 훅 스크립트(`waypoint-hook.sh`)와 같은 이름.
    public static let portEnvironmentKey = "WAYPOINT_PORT"
    /// 저장 폴더를 바꾸는 환경 변수. 훅·상태줄 스크립트와 같은 이름.
    public static let supportDirectoryEnvironmentKey = "WAYPOINT_SUPPORT_DIR"
    /// `0`이면 CloudKit 동기화를 끈다(테스트·확인용).
    public static let cloudKitEnvironmentKey = "WAYPOINT_CLOUDKIT"
    /// 빌드 때 정한 iCloud 동기화 스위치(Info.plist, build setting `WAYPOINT_ICLOUD`). `NO`면 끈다.
    /// 외부 베타 배포(`scripts/release-mac.sh`)는 기본으로 `NO`, 평소용·개발용·iOS는 `YES`이거나 키가 없다.
    public static let iCloudInfoKey = "WaypointICloud"

    /// 번들 ID가 없으면(명령행 도구·테스트) 평소용.
    public init(bundleIdentifier: String?) {
        self = bundleIdentifier?.hasSuffix(Self.devBundleSuffix) == true ? .dev : .stable
    }

    /// 지금 도는 프로세스의 인스턴스.
    public static let current = AppInstance(bundleIdentifier: Bundle.main.bundleIdentifier)

    public var defaultPort: UInt16 {
        switch self {
        case .stable: 47821
        case .dev: 47822
        }
    }

    /// `~/Library/Application Support/` 아래 폴더 이름.
    public var supportFolderName: String {
        switch self {
        case .stable: "Waypoint"
        case .dev: "Waypoint-Dev"
        }
    }

    public var isDev: Bool { self == .dev }

    /// 서버 포트. `WAYPOINT_PORT`가 1–65535 정수면 그 값, 아니면 기본값.
    public func port(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt16 {
        if let raw = environment[Self.portEnvironmentKey]?.trimmingCharacters(in: .whitespaces),
           let value = UInt16(raw), value > 0 {
            return value
        }
        return defaultPort
    }

    /// 저장 폴더. `WAYPOINT_SUPPORT_DIR`가 비어 있지 않으면 그 폴더(`~` 펼침), 아니면 `base/폴더 이름`.
    public func supportDirectory(
        base: URL, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let custom = environment[Self.supportDirectoryEnvironmentKey], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return base.appendingPathComponent(supportFolderName, isDirectory: true)
    }

    /// CloudKit 컨테이너. 엔타이틀먼트(`Config/*.entitlements`, build setting `WAYPOINT_CONTAINER`)와 같은 값이어야 한다.
    public var cloudKitContainerIdentifier: String {
        switch self {
        case .stable: "iCloud.dev.antaeho.waypoint"
        case .dev: "iCloud.dev.antaeho.waypoint.dev"
        }
    }

    /// 저장소를 미러링할 CloudKit 컨테이너. nil이면 동기화하지 않는다.
    /// - Info.plist `WaypointICloud`가 `NO`면 끈다(외부 베타 배포 빌드).
    /// - `WAYPOINT_CLOUDKIT=0`이면 끈다.
    /// - `WAYPOINT_SUPPORT_DIR`로 저장 폴더를 옮겼으면 끈다. 확인용 임시 저장소가 실제 컨테이너의 기록을 받아 오거나
    ///   임시 기록을 올려 섞지 않게.
    public func cloudKitContainer(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        info: [String: Any]? = Bundle.main.infoDictionary
    ) -> String? {
        if !Self.iCloudBuildEnabled(info: info) { return nil }
        if environment[Self.cloudKitEnvironmentKey]?.trimmingCharacters(in: .whitespaces) == "0" { return nil }
        if let custom = environment[Self.supportDirectoryEnvironmentKey], !custom.isEmpty { return nil }
        return cloudKitContainerIdentifier
    }

    /// 빌드 스위치(`WaypointICloud`)가 켜져 있는가. 키가 없거나 비었으면 켬(iOS·옛 빌드·테스트).
    /// 문자열 `NO`·`FALSE`·`0`(대소문자·앞뒤 공백 무시)이나 불리언 false면 끔.
    public static func iCloudBuildEnabled(info: [String: Any]?) -> Bool {
        switch info?[iCloudInfoKey] {
        case let flag as Bool:
            return flag
        case let text as String:
            let value = text.trimmingCharacters(in: .whitespaces).uppercased()
            return !["NO", "FALSE", "0"].contains(value)
        default:
            return true
        }
    }
}
