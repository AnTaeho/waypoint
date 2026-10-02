import AppKit
import Foundation
import Observation
import SwiftData
import WaypointKit

/// 기록 탭(TRK-47)의 동작: 지금 백업·복원 예약·내보내기·모든 기록 지우기. 버튼과 Debug 실행 인자가 같은 길을 쓴다.
/// 로직은 `Shared/Store`(`StoreBackup`·`StoreDailyBackup`·`RecordExport`·`RecordWipe`·`AppRelaunch`).
@MainActor
@Observable
final class RecordsModel {
    struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    private(set) var backups: [StoreBackup.Entry] = []
    private(set) var isBackingUp = false
    private(set) var notice: Notice?

    @ObservationIgnored let container: ModelContainer
    /// 떠 있는 동안의 백업(daily와 같은 진행 중 표시를 써 온라인 백업이 겹치지 않는다). 샘플 모드는 nil.
    @ObservationIgnored let daily: StoreDailyBackup?

    init(container: ModelContainer, daily: StoreDailyBackup?) {
        self.container = container
        self.daily = daily
    }

    var canBackUp: Bool { daily != nil }
    var backupFolder: URL? { daily?.backup.root }

    func reload() {
        backups = daily?.backup.list() ?? []
    }

    // MARK: - 백업·복원

    /// 열린 저장소를 `manual`로 뜬다(백그라운드). 다른 백업이 도는 중이면 그것이 끝난 것으로 본다.
    func backUpNow() async {
        guard let daily, !isBackingUp else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        // 지금 화면에서 바꾼 것까지 담도록 먼저 저장한다.
        try? container.mainContext.save()
        let result: Result<StoreBackup.Entry?, Error> = await Task.detached(priority: .utility) {
            Result { try daily.runNow(reason: .manual) }
        }.value
        switch result {
        case .success(let entry?):
            notice = Notice(text: "백업함 · " + RecordFormat.backupLine(entry, now: Date()), isError: false)
        case .success(nil):
            notice = Notice(text: "다른 백업이 도는 중", isError: true)
        case .failure(let error):
            notice = Notice(text: "백업 실패 · \(error.localizedDescription)", isError: true)
        }
        reload()
    }

    /// 다음 실행 때 이 백업으로 되돌리도록 적고 다시 시작한다(`StoreLaunch`가 열기 전에 지금 저장소를 `beforeRestore`로 옮긴다).
    func restore(_ entry: StoreBackup.Entry) {
        guard let daily else { return }
        do {
            try container.mainContext.save()
            try daily.backup.scheduleRestore(entry)
            NSLog("Waypoint 복원 예약 \(entry.id)")
            relaunch(failure: "다시 시작하지 못함 · 앱을 다시 열 때 되돌림")
        } catch {
            daily.backup.cancelScheduledRestore()
            notice = Notice(text: "복원 예약 실패 · \(error.localizedDescription)", isError: true)
        }
    }

    func showBackupsInFinder() {
        guard let folder = backupFolder else { return }
        if let latest = backups.first {
            NSWorkspace.shared.activateFileViewerSelecting([latest.url])
        } else {
            NSWorkspace.shared.open(folder.deletingLastPathComponent())
        }
    }

    // MARK: - 내보내기

    /// 전체(`project == nil`) 또는 프로젝트 하나를 `url`에 쓴다.
    @discardableResult
    func export(project: Project?, to url: URL) -> Bool {
        do {
            let document = try RecordExport.make(in: container.mainContext, project: project)
            try RecordExport.encode(document).write(to: url, options: .atomic)
            notice = Notice(text: "내보냄 · \(url.lastPathComponent)", isError: false)
            NSLog("Waypoint 내보내기 \(url.path)")
            return true
        } catch {
            notice = Notice(text: "내보내기 실패 · \(error.localizedDescription)", isError: true)
            return false
        }
    }

    // MARK: - 지우기

    func counts() -> RecordWipe.Counts {
        (try? RecordWipe.counts(in: container.mainContext)) ?? RecordWipe.Counts()
    }

    /// 지우기 전 백업(`beforeDelete`) → 모든 행 지우기 → 다시 시작. 백업이 안 되면 지우지 않는다.
    func wipeAll() {
        guard let daily else { return }
        do {
            let (entry, deleted) = try RecordWipe.backUpAndDeleteAll(in: container.mainContext) {
                try daily.runNow(reason: .beforeDelete)
            }
            NSLog("Waypoint 모든 기록 지움 \(deleted) · 백업 \(entry.id)")
            relaunch(failure: "지움 · 다시 시작하지 못함")
        } catch is RecordWipe.BackupBusy {
            notice = Notice(text: "다른 백업이 도는 중 · 지우지 않음", isError: true)
        } catch {
            notice = Notice(text: "지우지 못함 · \(error.localizedDescription)", isError: true)
        }
        reload()
    }

    // MARK: - 다시 시작

    /// 이 프로세스가 끝나기를 기다렸다가 같은 번들을 다시 여는 셸을 띄우고 끝낸다.
    func relaunch(failure: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", AppRelaunch.script(
            pid: ProcessInfo.processInfo.processIdentifier,
            bundlePath: Bundle.main.bundlePath,
            environment: ProcessInfo.processInfo.environment
        )]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            notice = Notice(text: failure, isError: true)
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
