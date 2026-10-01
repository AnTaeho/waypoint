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
    }
}
