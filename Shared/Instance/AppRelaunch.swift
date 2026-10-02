import Foundation

/// 앱 다시 시작(TRK-47 복원·지우기 뒤). 지금 프로세스가 끝나기를 기다렸다가 같은 번들을 다시 여는 작은 셸 명령.
///
/// - 같은 번들 경로를 연다: 평소용·Dev가 저마다 자기 자신만 다시 띄운다.
/// - `open`은 셸 환경을 앱에 넘기지 않는다. 저장 폴더·포트·iCloud 끄기 같은 변수는 `--env`로 그대로 넘긴다
///   (확인용 저장 폴더로 띄운 Dev가 기본 폴더로 다시 뜨면 예약 복원이 그 폴더에 없어 일어나지 않는다).
/// - 실행 인자는 넘기지 않는다(Debug 동작 인자가 다시 돌지 않게).
/// - 기다림은 최대 `timeout`초. 그때까지 안 끝나면 열지 않는다(죽어 가는 인스턴스를 다시 앞에 세우지 않게).
public enum AppRelaunch {

    /// 넘기는 환경 변수
    public static let forwardedKeys = [
        AppInstance.supportDirectoryEnvironmentKey, "WAYPOINT_PORT", "WAYPOINT_CLOUDKIT",
        "WAYPOINT_INTEGRATION_HOME", hiddenKey,
    ]
    /// 1이면 다시 열 때 뒤에서 숨긴 채(`open -g -j`). 확인용 실행이 화면을 가져가지 않게. 없으면 사람이 누른 복원·지우기라 앞에 연다.
    public static let hiddenKey = "WAYPOINT_RELAUNCH_HIDDEN"
    public static let timeout = 20

    /// `/bin/sh -c`에 넘길 명령.
    public static func script(pid: Int32, bundlePath: String, environment: [String: String]) -> String {
        var open = ["/usr/bin/open"]
        if environment[hiddenKey] == "1" { open += ["-g", "-j"] }
        for key in forwardedKeys {
            guard let value = environment[key], !value.isEmpty else { continue }
            open += ["--env", "\(key)=\(value)"]
        }
        open.append(bundlePath)
        let command = open.map(quote).joined(separator: " ")
        return "i=0; while /bin/kill -0 \(pid) 2>/dev/null; do i=$((i+1)); "
            + "[ $i -gt \(timeout * 5) ] && exit 1; /bin/sleep 0.2; done; \(command)"
    }

    /// 작은따옴표로 감싼다(안의 작은따옴표는 '\'' 로).
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
