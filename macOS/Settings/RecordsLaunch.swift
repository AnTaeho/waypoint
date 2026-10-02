import SwiftData
import SwiftUI
import WaypointKit

/// 손 없이 기록 탭을 확인할 때의 Debug 전용 실행 인자(TRK-47). 버튼과 같은 `RecordsModel` 길을 쓴다(대화상자만 건너뛴다).
/// 확인용 저장 폴더(`WAYPOINT_SUPPORT_DIR`)와 함께만 쓴다. 순서대로 돈다.
/// - `-WaypointSettingsTab records`: 설정 창을 「기록」 탭으로 연다(`SettingsTab.storageKey`).
/// - `-WaypointExport <경로>` (+ `-WaypointExportProject <키>`): 저장 대화상자 없이 그 경로로 내보낸다.
/// - `-WaypointBackupNow 1`: 「지금 백업」.
/// - `-WaypointRestore <백업 폴더 이름|latest>`: 그 백업으로 복원 예약 → 다시 시작.
/// - `-WaypointWipe 1`: 모든 기록 지우기 → 다시 시작.
/// 다시 시작한 앱에는 실행 인자를 넘기지 않으므로(`AppRelaunch`) 되풀이하지 않는다.
@MainActor
enum RecordsLaunch {
    static func start(_ model: RecordsModel) {
        #if DEBUG
        let defaults = UserDefaults.standard
        let export = defaults.string(forKey: "WaypointExport")
        let exportKey = defaults.string(forKey: "WaypointExportProject")
        let backUp = defaults.string(forKey: "WaypointBackupNow") != nil
        let restore = defaults.string(forKey: "WaypointRestore")
        let wipe = defaults.string(forKey: "WaypointWipe") != nil
        guard export != nil || backUp || restore != nil || wipe else { return }
        Task {
            if let export {
                let projects = (try? model.container.mainContext.fetch(FetchDescriptor<Project>())) ?? []
                let project = exportKey.flatMap { key in projects.first { $0.key == key } }
                model.export(project: project, to: URL(fileURLWithPath: export))
            }
            if backUp { await model.backUpNow() }
            if let restore {
                model.reload()
                let entry = restore == "latest" ? model.backups.first : model.backups.first { $0.id == restore }
                if let entry { model.restore(entry) } else { NSLog("Waypoint 복원할 백업 없음 \(restore)") }
            }
            if wipe { model.wipeAll() }
            if let notice = model.notice { NSLog("Waypoint 기록 탭 \(notice.text)") }
        }
        #endif
    }
}

extension View {
    /// Debug: `-WaypointSettingsTab`이 있으면 메인 창이 뜰 때 설정 창을 한 번 연다.
    func settingsLaunch() -> some View {
        modifier(SettingsLaunch())
    }
}

private struct SettingsLaunch: ViewModifier {
    @Environment(\.openSettings) private var openSettings
    @MainActor private static var opened = false

    func body(content: Content) -> some View {
        content.onAppear {
            #if DEBUG
            guard !Self.opened, UserDefaults.standard.string(forKey: SettingsTab.storageKey) != nil,
                  ProcessInfo.processInfo.arguments.contains("-\(SettingsTab.storageKey)") else { return }
            Self.opened = true
            openSettings()
            #endif
        }
    }
}
