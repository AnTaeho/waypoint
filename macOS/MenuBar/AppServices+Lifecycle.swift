import AppKit
import Foundation

extension AppServices {
    /// 앱으로 돌아오거나 잠자기에서 깨어났을 때 타이머를 기다리지 않는다.
    func observeLifecycle() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStates()
                self?.guidance?.refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStates() }
        }
        // 끝내기 직전에 점검 주기를 기다리던 지표·진단 기록과 저장 안 된 변경을 쓴다. 메인 스레드에서 바로 돈다.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveBeforeTerminate() }
        }
    }

    func saveBeforeTerminate() {
        reliability.saveIfNeeded()
        integration.saveIfNeeded()
        let context = container.mainContext
        if context.hasChanges { try? context.save() }
    }
}
