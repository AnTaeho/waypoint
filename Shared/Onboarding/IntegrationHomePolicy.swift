import Foundation

/// 연동 설치·진단이 보는 홈과, 설치를 막는 조건.
/// Dev 앱이 실제 홈에 설치하면 평소용 연결을 47822로 바꿔 끼워 평소용 기록이 끊긴다. 그래서 Dev는 실제 홈에 설치하지 않는다.
/// Debug 빌드는 `WAYPOINT_INTEGRATION_HOME`으로 임시 홈을 주면 그 홈에 설치할 수 있다(실측·화면 확인용).
public enum IntegrationHomePolicy {
    public static let environmentKey = "WAYPOINT_INTEGRATION_HOME"

    /// Dev가 실제 홈에 설치하려 할 때 화면에 보이는 까닭
    public static let devBlockReason = "Waypoint Dev는 평소용 연결을 바꾸지 않음"

    /// 설치기·진단이 볼 홈. `allowOverride`(Debug 빌드)이고 환경 변수가 비어 있지 않으면 그 폴더(`~` 펼침), 아니면 실제 홈.
    public static func home(environment: [String: String] = ProcessInfo.processInfo.environment,
                            allowOverride: Bool, realHome: URL) -> URL {
        if allowOverride, let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return realHome
    }

    /// 설치·해제를 막는 까닭. 막지 않으면 nil. Dev이고 홈이 실제 홈(링크를 푼 경로 비교)이면 막는다.
    public static func installBlock(instance: AppInstance, home: URL, realHome: URL) -> String? {
        guard instance.isDev else { return nil }
        return same(home, realHome) ? devBlockReason : nil
    }

    static func same(_ a: URL, _ b: URL) -> Bool {
        normalized(a) == normalized(b)
    }

    private static func normalized(_ url: URL) -> String {
        var path = IntegrationFile.resolved(url.standardizedFileURL.path)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
