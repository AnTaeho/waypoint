import Foundation
import Observation
import Sparkle
import WaypointKit

/// 자동 업데이트(TRK-56). Info.plist에 피드 주소와 공개 키가 있을 때만 만든다(`UpdateFeed`).
/// 찾기·내려받기·서명 확인·설치·재실행 창은 Sparkle 표준 화면이 맡는다. 설치가 실패하면 앱은 그대로 남고,
/// 새 빌드로 처음 열 때 저장소를 백업한다(TRK-46 `store-version.json`).
@MainActor
@Observable
final class AppUpdater {
    /// 지금 확인을 시작할 수 있는가(확인·설치 중이면 false)
    private(set) var canCheck = false
    /// 정해진 간격(기본 하루)으로 저절로 확인하는가. 처음 값은 Info.plist `SUEnableAutomaticChecks`(켬)
    var automaticallyChecks: Bool {
        didSet {
            guard controller.updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// 이 빌드에 업데이트 피드가 없으면 nil(평소용·Dev 기본)
    static func forCurrentApp() -> AppUpdater? {
        guard UpdateFeed(info: Bundle.main.infoDictionary) != nil else { return nil }
        return AppUpdater()
    }

    private init() {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        canCheck = controller.updater.canCheckForUpdates
        // Sparkle은 이 값들을 메인 스레드에서 바꾼다
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    guard let self, self.automaticallyChecks != updater.automaticallyChecksForUpdates else { return }
                    self.automaticallyChecks = updater.automaticallyChecksForUpdates
                }
            },
        ]
    }

    /// 지금 확인. 결과(새 판 있음·최신임·실패)는 Sparkle 창이 보여 준다
    func checkNow() {
        controller.checkForUpdates(nil)
    }
}
