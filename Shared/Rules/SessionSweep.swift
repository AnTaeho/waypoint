import Foundation
import SwiftData

/// `SessionEnd` 훅이 오지 않은 세션 정리(SPEC 5장 「종료 판정」).
/// Claude Code 2.1.283 실측에서 `-p` 세션 20개 중 3개가 `SessionEnd` 없이 끝났다.
/// - PID를 아는 세션: 그 프로세스가 없으면(또는 마지막 훅 뒤에 시작한 다른 프로세스면) 끝난 것으로 본다.
/// - PID를 모르는 세션: 마지막 활동에서 24시간이 지나면 끝낸다.
public enum SessionSweep {

    /// PID를 모르는 세션을 끝내는 무활동 시간(24시간).
    public static let inactiveLimit: TimeInterval = 24 * 60 * 60
    /// 프로세스 시작 시각 비교 여유(초). outbox `receivedAt`은 초 단위로 잘린다.
    public static let startTolerance: TimeInterval = 2

    public static let reasonProcessGone = "process-gone"
    public static let reasonInactive = "inactive-24h"

    /// 살아 있는 프로세스 정보. 없는 프로세스(좀비 포함)는 probe가 nil을 돌려준다.
    public struct ProcessStatus: Equatable, Sendable {
        /// 프로세스 시작 시각. 모르면 nil(PID 재사용 검사를 건너뛴다).
        public var startedAt: Date?
        public init(startedAt: Date?) { self.startedAt = startedAt }
    }

    /// PID → 살아 있으면 정보, 없으면 nil. 앱에서는 `SessionSweep.systemProbe(_:)`(macOS), 테스트에서는 가짜.
    public typealias Probe = (Int) -> ProcessStatus?

    public enum Verdict: Equatable, Sendable {
        case keep
        case end(reason: String)
    }

    /// 끝나지 않은 메인 세션 하나의 판정. 순수 함수.
    /// - PID가 있으면 프로세스를 본다. 없거나, 시작 시각이 `lastSeenAt`보다(여유 포함) 늦으면 → `process-gone`.
    ///   마지막 훅 뒤에 시작한 프로세스는 그 훅을 보냈을 수 없으니 PID를 재사용한 다른 프로세스다.
    /// - PID가 없으면 `now - lastSeenAt > inactiveLimit`일 때 → `inactive-24h`.
    public static func verdict(
        pid: Int?,
        lastSeenAt: Date,
        now: Date,
        inactiveLimit: TimeInterval = inactiveLimit,
        probe: Probe
    ) -> Verdict {
        if let pid {
            guard let process = probe(pid) else { return .end(reason: reasonProcessGone) }
            if let started = process.startedAt, started.timeIntervalSince(lastSeenAt) > startTolerance {
                return .end(reason: reasonProcessGone)
            }
            return .keep
        }
        return now.timeIntervalSince(lastSeenAt) > inactiveLimit ? .end(reason: reasonInactive) : .keep
    }
}

extension HookProcessor {
    /// 끝나지 않은 메인 세션을 판정해 끝낼 것은 `finish`로 끝내고(하위 세션·카드 연결 포함, `session.end`에 `reason`) 저장한다.
    /// 끝낸 시각은 `now`, 마지막 활동(`lastSeenAt`)은 그대로 둔다. 그 뒤 시각의 훅이 오면 세션은 다시 살아난다(`mainSession`).
    /// 끝낸 세션 수를 돌려준다.
    @discardableResult
    public func sweep(now: Date, inactiveLimit: TimeInterval = SessionSweep.inactiveLimit, probe: SessionSweep.Probe) -> Int {
        let mainKind = SessionKind.main.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.endedAt == nil && $0.kindRaw == mainKind }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        var ended = 0
        for session in sessions {
            let verdict = SessionSweep.verdict(
                pid: session.claudePid, lastSeenAt: session.lastSeenAt, now: now,
                inactiveLimit: inactiveLimit, probe: probe
            )
            guard case .end(let reason) = verdict else { continue }
            finish(session, at: now, reason: reason, activity: false)
            ended += 1
        }
        guard ended > 0 else { return 0 }
        do {
            try context.save()
        } catch {
            context.rollback()
            return 0
        }
        return ended
    }
}

#if os(macOS)
import Darwin

extension SessionSweep {
    /// `sysctl(KERN_PROC_PID)`로 프로세스를 본다. 없거나 좀비면 nil, 있으면 `p_starttime`.
    /// (실행 파일 이름 `p_comm`은 쓰지 않는다: 네이티브 설치의 claude는 버전 번호 `2.1.283`으로 나온다.)
    @Sendable public static func systemProbe(_ pid: Int) -> ProcessStatus? {
        guard pid > 1, pid <= Int(Int32.max) else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        guard info.kp_proc.p_pid == Int32(pid), info.kp_proc.p_stat != SZOMB else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = start.tv_sec > 0
            ? Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
            : nil
        return ProcessStatus(startedAt: started)
    }
}
#endif
