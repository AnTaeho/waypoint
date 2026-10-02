import Foundation

/// 떠 있는 동안의 `daily` 백업(TRK-46). 평소용은 로그인 항목이라 거의 다시 시작하지 않아 실행 때 판정만으로는 드물게 돈다.
/// 주기 점검이 `startIfDue`를 부르면, 마지막 백업이 24시간보다 오래됐을 때 열린 저장소를 SQLite 온라인 백업으로 뜬다.
/// 백그라운드 큐에서 돌고 한 번에 하나만. 실패하면 아무것도 남기지 않고 다음 점검에서 다시 판정한다.
public final class StoreDailyBackup: @unchecked Sendable {
    public let backup: StoreBackup
    public let stamp: StoreVersionStamp
    private let lock = NSLock()
    private var running = false
    /// 마지막 백업 시각(디스크를 10초마다 읽지 않게 기억)
    private var lastBackupAt: Date?

    public init(storeURL: URL, stamp: StoreVersionStamp) {
        backup = StoreBackup(storeURL: storeURL)
        self.stamp = stamp
    }

    /// 지금 떠야 하면 진행 중 표시를 하고 true. 진행 중이거나 하루가 안 됐으면 false.
    func claim(now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return false }
        if let last = lastBackupAt, now.timeIntervalSince(last) < StoreBackup.dailyInterval { return false }
        lastBackupAt = backup.list().first?.info.createdAt
        guard backup.storeExists, backup.isDailyDue(now: now) else { return false }
        running = true
        return true
    }

    func finish(_ entry: StoreBackup.Entry?) {
        lock.lock()
        defer { lock.unlock() }
        running = false
        if let entry { lastBackupAt = entry.info.createdAt }
    }

    /// 판정과 백업을 이 스레드에서 한다. 떴으면 그 백업.
    @discardableResult
    public func runIfDue(now: Date) throws -> StoreBackup.Entry? {
        guard claim(now: now) else { return nil }
        do {
            let entry = try backup.backupOpenStore(reason: .daily, stamp: stamp, at: now)
            finish(entry)
            return entry
        } catch {
            finish(nil)
            throw error
        }
    }

    /// 지금 바로 뜬다(기록 탭 「지금 백업」·지우기 전, TRK-47). 24시간 판정은 보지 않고, 다른 백업이 도는 중이면 nil.
    /// 온라인 백업과 정리(`prune`)가 겹치지 않게 daily와 같은 진행 중 표시를 쓴다. 부른 스레드에서 돈다.
    @discardableResult
    public func runNow(reason: StoreBackup.Reason, now: Date = Date()) throws -> StoreBackup.Entry? {
        guard claimNow() else { return nil }
        do {
            let entry = try backup.backupOpenStore(reason: reason, stamp: stamp, at: now)
            finish(entry)
            return entry
        } catch {
            finish(nil)
            throw error
        }
    }

    func claimNow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return false }
        running = true
        return true
    }

    /// 판정은 부른 스레드에서, 백업은 백그라운드 큐에서. 시작했으면 true.
    @discardableResult
    public func startIfDue(now: Date = Date()) -> Bool {
        guard claim(now: now) else { return false }
        DispatchQueue.global(qos: .utility).async { [self] in
            let entry = try? backup.backupOpenStore(reason: .daily, stamp: stamp, at: now)
            finish(entry)
        }
        return true
    }
}
