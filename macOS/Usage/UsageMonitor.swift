import Foundation
import Observation
import WaypointKit

/// 사용량 파일을 30초마다 확인해 바뀌었을 때만 다시 읽는다.
/// - Claude: 저장 폴더의 `usage.json`. 중계 스크립트가 임시 파일 → mv로 바꿔 끼우므로 파일 감시(DispatchSource)는
///   교체 때마다 끊기고, 폴더 감시는 같은 폴더의 저장소·outbox 변화에도 깨어나서 수정 시각만 보는 폴링이 가장 단순하다.
/// - 세션 이름·컨텍스트 사용률: 같은 폴더의 `session-status.json`, 같은 방식.
/// - Codex: `~/.codex/sessions`(또는 `$CODEX_HOME/sessions`) 최근 날짜 폴더의 기록 파일 끝부분.
@MainActor
@Observable
final class UsageMonitor {
    private(set) var claude: UsageSnapshot?
    private(set) var codex: UsageGroup?
    /// 세션 ID별 이름·컨텍스트 사용률. 오래된 사용률은 확인할 때마다 걸러 낸다.
    private(set) var sessionLines: [String: SessionStatusLine] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var claudeModified: Date?
    @ObservationIgnored private let claudeURL: URL?
    @ObservationIgnored private let sessionsURL: URL?
    @ObservationIgnored private var sessionsModified: Date?
    @ObservationIgnored private var sessions = SessionStatusSnapshot()
    @ObservationIgnored private let codexSessions = CodexUsage.sessionsDirectory()
    /// 지난번에 본 가장 최근 기록 파일과 값을 준 파일(경로·수정 시각). 둘 다 그대로면 다시 읽지 않는다.
    @ObservationIgnored private var codexKey: [CodexUsage.Candidate] = []

    static let pollInterval: TimeInterval = 30

    init() {
        let folder = try? WaypointStore.supportDirectory(create: false)
        claudeURL = folder?.appendingPathComponent(UsageSnapshot.fileName)
        sessionsURL = folder?.appendingPathComponent(SessionStatusSnapshot.fileName)
    }

    /// 이 세션 줄에 얹을 이름·사용률. Claude Code 메인 세션만 값이 있다.
    func status(for session: Session) -> SessionStatusLine {
        guard session.provider == .claude, session.kind == .main else { return .none }
        return sessionLines[session.id] ?? .none
    }

    /// 보일 묶음: 기록이 있고 설정에서 켠 도구만, Claude → Codex 순
    func groups(showClaude: Bool, showCodex: Bool) -> [UsageGroup] {
        [showClaude ? claude?.group : nil, showCodex ? codex : nil]
            .compactMap { $0 }
            .filter { !$0.limits.isEmpty }
    }

    /// 한 번 바로 읽고 30초마다 다시 확인한다. 두 번 불러도 타이머는 하나.
    func start() {
        guard timer == nil else { return }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func reload() {
        reloadClaude()
        reloadSessions()
        reloadCodex()
    }

    private func reloadSessions() {
        guard let sessionsURL else { return }
        let modified = (try? FileManager.default.attributesOfItem(atPath: sessionsURL.path))?[.modificationDate] as? Date
        if modified != sessionsModified {
            sessionsModified = modified
            sessions = modified == nil ? .init() : SessionStatusSnapshot.load(from: sessionsURL)
        }
        let next = sessions.lines(now: Date())
        if next != sessionLines { sessionLines = next }
    }

    private func reloadClaude() {
        guard let claudeURL else { return }
        // URL.resourceValues는 값을 캐시하므로 매번 파일 속성을 새로 읽는다.
        let modified = (try? FileManager.default.attributesOfItem(atPath: claudeURL.path))?[.modificationDate] as? Date
        guard let modified else {
            // 파일이 사라지면 게이지도 숨긴다.
            claudeModified = nil
            if claude != nil { claude = nil }
            return
        }
        guard modified != claudeModified else { return }
        claudeModified = modified
        let next = UsageSnapshot.load(from: claudeURL)
        if next != claude { claude = next }
    }

    private func reloadCodex() {
        let candidates = CodexUsage.candidates(in: codexSessions)
        // 가장 최근 파일과 지난번 값을 준 파일이 그대로면 결과도 같다.
        if let newest = candidates.first, codexKey.first == newest, codexKey.dropFirst().allSatisfy(candidates.contains) {
            return
        }
        let hit = CodexUsage.latest(in: candidates)
        codexKey = candidates.first.map { [$0] + (hit.map { [$0.source] } ?? []) } ?? []
        let next = hit?.group
        if next != codex { codex = next }
    }
}
