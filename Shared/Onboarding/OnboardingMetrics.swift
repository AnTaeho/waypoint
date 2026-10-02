import Foundation

/// 첫 연결 지표(TRK-45). 온보딩을 한 번 연 것(열기 → 「끝」 또는 닫기)을 한 「시도」로 보고 단계별 시각·실패 지점·다시 시도 횟수를 남긴다.
/// `ReliabilityMetrics.onboarding`으로 저장 폴더 `metrics.json`에 들어간다. 숫자·시각·정수 enum만 담는다.
/// 경로·프로젝트 키·세션 ID·오류 문구를 담을 문자열 필드가 없다(`OnboardingMetricsTests`가 고정).
public struct OnboardingMetrics: Codable, Equatable, Sendable {
    /// 남기는 최근 시도 수
    public static let attemptLimit = 20

    /// 오래된 것부터
    public var attempts: [Attempt] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attempts = (try? c.decodeIfPresent([Attempt].self, forKey: .attempts)) ?? []
    }

    /// 온보딩 단계. 값은 저장 형식이라 바꾸지 않는다.
    public enum Stage: Int, Codable, Comparable, CaseIterable, Sendable {
        case tools = 0, install = 1, project = 2, receive = 3, done = 4

        public init(_ step: OnboardingProgress.Step) {
            switch step {
            case .tools: self = .tools
            case .install: self = .install
            case .project: self = .project
            case .receive: self = .receive
            case .done: self = .done
            }
        }

        public init(from decoder: Decoder) throws {
            self = Stage(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .tools
        }

        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .tools: "도구"
            case .install: "연결"
            case .project: "프로젝트"
            case .receive: "첫 기록"
            case .done: "끝"
            }
        }
    }

    /// 도구. 값은 저장 형식이라 바꾸지 않는다.
    public enum Tool: Int, Codable, Sendable {
        case claude = 0, codex = 1

        public init(_ provider: AgentProvider) { self = provider == .codex ? .codex : .claude }
        public var provider: AgentProvider { self == .codex ? .codex : .claude }
    }

    /// 멈춘 까닭의 종류. 원문은 남기지 않는다. 값은 저장 형식이라 바꾸지 않는다(모르는 값은 `other`).
    public enum Reason: Int, Codable, CaseIterable, Sendable {
        case other = 0
        /// 설치: 설정 파일을 읽을 수 없음
        case unreadable = 1
        /// 설치: 직접 고친 설정과 겹침
        case conflict = 2
        /// 설치: 앱 안 연결 파일 없음
        case missingResource = 3
        /// 설치: 확인하는 사이 파일이 바뀜
        case changedSincePlan = 4
        /// 설치: 백업 실패
        case backupFailed = 5
        /// 설치: 쓰기 실패
        case writeFailed = 6
        /// 부분 실패: 파일은 썼지만 명령 단계(`claude mcp add`)가 실패
        case commandFailed = 7
        /// 부분 실패: 명령 단계의 `claude` 실행 파일을 찾지 못함
        case commandMissing = 8
        /// 설치 준비 실패(설치 문맥을 만들지 못함 등)
        case setupUnavailable = 9
        /// Dev 앱이 실제 홈에 설치하려 함
        case devBlocked = 10
        /// 설치돼 있지만 확인 필요(다른 포트·꺼짐 등)
        case attention = 11
        /// 보관된 프로젝트 폴더
        case archivedProject = 12
        /// 기록 받는 서버가 준비되지 않음
        case serverDown = 13
        /// 기록이 왔지만 등록된 폴더 밖
        case unlinked = 14

        public init(from decoder: Decoder) throws {
            self = Reason(rawValue: try decoder.singleValueContainer().decode(Int.self)) ?? .other
        }

        public init(_ error: IntegrationInstallError) {
            switch error {
            case .unreadable: self = .unreadable
            case .conflict: self = .conflict
            case .missingResource: self = .missingResource
            case .changedSincePlan: self = .changedSincePlan
            case .backupFailed: self = .backupFailed
            case .writeFailed: self = .writeFailed
            }
        }

        /// 다른 오류(설치 문맥을 만들지 못함 등)
        public init(error: Error) {
            if let error = error as? IntegrationInstallError { self.init(error) } else { self = .setupUnavailable }
        }

        /// 명령 단계 결과. 끝났으면 nil
        public init?(_ outcome: IntegrationInstaller.StepOutcome) {
            switch outcome {
            case .done: return nil
            case .executableMissing: self = .commandMissing
            case .failed: self = .commandFailed
            }
        }

        /// 화면 판정의 막힘 중 실패로 셀 것. 기다림·고르지 않음 같은 보통 상태는 nil
        public static func blocker(_ blocker: OnboardingProgress.Blocker) -> (Reason, Tool?)? {
            switch blocker {
            case .installBlocked: (.devBlocked, nil)
            case .attention(let provider, _): (.attention, Tool(provider))
            case .archivedProject: (.archivedProject, nil)
            case .serverDown: (.serverDown, nil)
            case .unlinked(let provider): (.unlinked, Tool(provider))
            case .noToolSelected, .notInstalled, .noProject, .pendingRegistration, .waiting: nil
            }
        }

        public var title: String {
            switch self {
            case .other: "기타"
            case .unreadable: "설정 읽기 실패"
            case .conflict: "설정 겹침"
            case .missingResource: "앱 연결 파일 없음"
            case .changedSincePlan: "확인 중 파일 바뀜"
            case .backupFailed: "백업 실패"
            case .writeFailed: "쓰기 실패"
            case .commandFailed: "등록 명령 실패"
            case .commandMissing: "claude 실행 파일 없음"
            case .setupUnavailable: "설치 준비 실패"
            case .devBlocked: "Dev 차단"
            case .attention: "확인 필요"
            case .archivedProject: "보관된 프로젝트"
            case .serverDown: "서버 안 뜸"
            case .unlinked: "등록 밖 폴더"
            }
        }
    }

    /// 도구별 시각
    public struct ToolTimes: Codable, Equatable, Sendable {
        public var claude: Date?
        public var codex: Date?
        public init(claude: Date? = nil, codex: Date? = nil) { self.claude = claude; self.codex = codex }
        public subscript(tool: Tool) -> Date? {
            get { tool == .codex ? codex : claude }
            set { if tool == .codex { codex = newValue } else { claude = newValue } }
        }
        public var earliest: Date? { [claude, codex].compactMap { $0 }.min() }
    }

    /// 실패 한 종류. 같은 (단계, 까닭, 도구)는 한 줄로 모으고 횟수를 센다.
    public struct Failure: Codable, Equatable, Sendable {
        public var stage: Stage
        public var reason: Reason
        public var tool: Tool?
        /// 처음 본 시각
        public var at: Date
        public var count: Int
        public init(stage: Stage, reason: Reason, tool: Tool?, at: Date, count: Int = 1) {
            self.stage = stage; self.reason = reason; self.tool = tool; self.at = at; self.count = count
        }
    }

    /// 한 번 연 온보딩
    public struct Attempt: Codable, Equatable, Sendable {
        public var startedAt: Date
        /// 마지막으로 보인 단계
        public var lastStage: Stage = .tools
        /// 가장 멀리 간 단계
        public var furthestStage: Stage = .tools
        /// 도구별 연결 적용 성공(이미 연결돼 있던 것을 확인한 시각 포함)
        public var installed = ToolTimes()
        /// 프로젝트를 고르고 등록까지 된 시각(이미 등록된 프로젝트로 넘어간 시각 포함)
        public var projectAt: Date?
        /// 도구별 첫 기록 수신 시각(시작 이후 활동, 프로젝트에 연결된 것)
        public var firstRecord = ToolTimes()
        /// 「끝」
        public var finishedAt: Date?
        /// 닫기(미완)
        public var closedAt: Date?
        /// 다시 시도(연결 다시 시도·서버 다시 시도)
        public var retries = 0
        public var failures: [Failure] = []

        public init(startedAt: Date) { self.startedAt = startedAt }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            startedAt = try c.decode(Date.self, forKey: .startedAt)
            lastStage = (try? c.decodeIfPresent(Stage.self, forKey: .lastStage)) ?? .tools
            furthestStage = (try? c.decodeIfPresent(Stage.self, forKey: .furthestStage)) ?? .tools
            installed = (try? c.decodeIfPresent(ToolTimes.self, forKey: .installed)) ?? ToolTimes()
            projectAt = try? c.decodeIfPresent(Date.self, forKey: .projectAt)
            firstRecord = (try? c.decodeIfPresent(ToolTimes.self, forKey: .firstRecord)) ?? ToolTimes()
            finishedAt = try? c.decodeIfPresent(Date.self, forKey: .finishedAt)
            closedAt = try? c.decodeIfPresent(Date.self, forKey: .closedAt)
            retries = (try? c.decodeIfPresent(Int.self, forKey: .retries)) ?? 0
            failures = (try? c.decodeIfPresent([Failure].self, forKey: .failures)) ?? []
        }

        /// 끝났거나 닫혔다
        public var isEnded: Bool { finishedAt != nil || closedAt != nil }

        /// 시작 → 그 도구의 첫 기록(초)
        public func timeToFirstRecord(_ tool: Tool) -> TimeInterval? {
            firstRecord[tool].map { max(0, $0.timeIntervalSince(startedAt)) }
        }

        /// 시작 → 어느 도구든 첫 기록(초)
        public var timeToAnyRecord: TimeInterval? {
            firstRecord.earliest.map { max(0, $0.timeIntervalSince(startedAt)) }
        }
    }

    // MARK: - 기록

    /// 온보딩을 열었다. 이전 시도가 열린 채면(앱 종료 등) 그대로 둔다(미완으로 센다).
    public mutating func start(at date: Date) {
        attempts.append(Attempt(startedAt: date))
        if attempts.count > Self.attemptLimit { attempts.removeFirst(attempts.count - Self.attemptLimit) }
    }

    /// `startedAt`이 같은 열린 시도를 고친다. 없으면(끝났거나 밀려남) 아무것도 하지 않는다.
    private mutating func update(_ startedAt: Date, _ change: (inout Attempt) -> Void) {
        guard let index = attempts.lastIndex(where: { $0.startedAt == startedAt }), !attempts[index].isEnded else { return }
        change(&attempts[index])
    }

    public mutating func reach(_ stage: Stage, attempt: Date) {
        update(attempt) { $0.lastStage = stage; $0.furthestStage = max($0.furthestStage, stage) }
    }

    /// 처음 한 번만 남긴다
    public mutating func installed(_ tool: Tool, at date: Date, attempt: Date) {
        update(attempt) { if $0.installed[tool] == nil { $0.installed[tool] = date } }
    }

    public mutating func projectRegistered(at date: Date, attempt: Date) {
        update(attempt) { if $0.projectAt == nil { $0.projectAt = date } }
    }

    /// 처음 한 번만 남긴다. 시작 전 시각은 받지 않는다.
    public mutating func firstRecord(_ tool: Tool, at date: Date, attempt: Date) {
        update(attempt) { if $0.firstRecord[tool] == nil, date >= $0.startedAt { $0.firstRecord[tool] = date } }
    }

    public mutating func fail(_ stage: Stage, _ reason: Reason, tool: Tool? = nil, at date: Date, attempt: Date) {
        update(attempt) { a in
            if let i = a.failures.firstIndex(where: { $0.stage == stage && $0.reason == reason && $0.tool == tool }) {
                a.failures[i].count += 1
            } else {
                a.failures.append(Failure(stage: stage, reason: reason, tool: tool, at: date))
            }
        }
    }

    public mutating func retried(attempt: Date) {
        update(attempt) { $0.retries += 1 }
    }

    public mutating func finish(at date: Date, attempt: Date) {
        update(attempt) { $0.finishedAt = date; $0.lastStage = .done; $0.furthestStage = .done }
    }

    public mutating func close(at date: Date, attempt: Date) {
        update(attempt) { $0.closedAt = date }
    }

    /// 화면 판정 한 번을 지표로 옮긴다(온보딩 화면이 판정이 바뀔 때마다 부른다). 시도는 `input.startedAt`으로 찾는다.
    /// 막힘은 바로 앞 판정과 다를 때만 실패로 센다(같은 막힘이 다시 그려질 때 늘지 않게).
    public mutating func observe(_ progress: OnboardingProgress, previous: OnboardingProgress.Blocker?, at date: Date) {
        let input = progress.input
        let attempt = input.startedAt
        reach(Stage(progress.step), attempt: attempt)
        for provider in progress.tools where input.installations[provider]?.state == .ready {
            installed(Tool(provider), at: date, attempt: attempt)
        }
        if case .registered = input.project {
            projectRegistered(at: date, attempt: attempt)
        } else if progress.step > .project {
            projectRegistered(at: date, attempt: attempt)
        }
        for provider in progress.tools {
            guard let receipt = input.receipts[provider], receipt.at >= input.startedAt, receipt.project != nil else { continue }
            firstRecord(Tool(provider), at: max(receipt.receivedAt, input.startedAt), attempt: attempt)
        }
        if let blocker = progress.blocker, blocker != previous, let (reason, tool) = Reason.blocker(blocker) {
            fail(Stage(progress.step), reason, tool: tool, at: date, attempt: attempt)
        }
    }

    // MARK: - 요약

    public struct Summary: Equatable, Sendable {
        public var attempts: Int
        public var finished: Int
        /// 마지막 시도
        public var last: Attempt?
        /// 「끝」낸 시도들의 시작 → 첫 기록(어느 도구든) 중앙값(초)
        public var medianToFirstRecord: TimeInterval?
        /// 미완 시도들이 가장 많이 멈춘 단계와 그 횟수. 같으면 앞 단계
        public var mostStopped: Stop?
    }

    public struct Stop: Equatable, Sendable {
        public var stage: Stage
        public var count: Int
    }

    /// 마지막 시도가 열려 있으면 진행 중으로 보고 「멈춘 단계」에서 뺀다. 그보다 앞의 열린 시도는 앱이 꺼진 것이라 미완으로 센다.
    public var summary: Summary {
        let finished = attempts.filter { $0.finishedAt != nil }
        let durations = finished.compactMap(\.timeToAnyRecord).sorted()
        // 중앙값: 짝수면 가운데 둘의 평균
        let median: TimeInterval? = durations.isEmpty ? nil
            : durations.count % 2 == 1 ? durations[durations.count / 2]
            : (durations[durations.count / 2 - 1] + durations[durations.count / 2]) / 2
        var stopped = attempts.enumerated().filter { $0.element.finishedAt == nil }
        if let last = attempts.last, !last.isEnded { stopped.removeAll { $0.offset == attempts.count - 1 } }
        var counts: [Stage: Int] = [:]
        for (_, attempt) in stopped { counts[attempt.lastStage, default: 0] += 1 }
        let most = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }
        return Summary(attempts: attempts.count, finished: finished.count, last: attempts.last,
                       medianToFirstRecord: median, mostStopped: most.map { Stop(stage: $0.key, count: $0.value) })
    }

    /// 연동 상태 패널의 한두 줄. 시도가 없으면 빈 배열.
    public func panelLines() -> [String] {
        let s = summary
        guard let last = s.last else { return [] }
        var parts: [String] = []
        if let recent = last.timeToAnyRecord { parts.append("최근 \(ReliabilityMetrics.duration(recent))") }
        if let median = s.medianToFirstRecord { parts.append("중앙값 \(ReliabilityMetrics.duration(median)) (\(s.finished)회)") }
        var lines = ["첫 기록까지 · " + (parts.isEmpty ? "아직 없음" : parts.joined(separator: " · "))]
        if let stop = s.mostStopped { lines.append("자주 멈춘 단계 · \(stop.stage.title) (\(stop.count)회)") }
        return lines
    }

    /// 진단 내보내기 줄. 숫자·시각·단계 이름만.
    public func diagnosticLines() -> [String] {
        let s = summary
        guard let last = s.last else { return ["첫 연결: 시도 없음"] }
        func time(_ value: TimeInterval?) -> String { value.map(ReliabilityMetrics.duration) ?? "없음" }
        var lines = [
            "첫 연결: 시도 \(s.attempts)회 · 끝냄 \(s.finished)회",
            "마지막 시도: \(last.startedAt.ISO8601Format()) 시작 · 단계 \(last.lastStage.title)"
                + (last.finishedAt != nil ? " · 끝냄" : last.closedAt != nil ? " · 닫음" : "")
                + " · 다시 시도 \(last.retries)회",
            "마지막 시도 시작→첫 기록: " + AgentProvider.allCases.map {
                "\($0.name) \(time(last.timeToFirstRecord(Tool($0))))"
            }.joined(separator: " · "),
            "마지막 시도 시작→연결·프로젝트: " + AgentProvider.allCases.map {
                "\($0.name) 연결 \(time(last.installed[Tool($0)].map { max(0, $0.timeIntervalSince(last.startedAt)) }))"
            }.joined(separator: " · ") + " · 프로젝트 \(time(last.projectAt.map { max(0, $0.timeIntervalSince(last.startedAt)) }))",
            "끝낸 시도 시작→첫 기록 중앙값: " + (s.medianToFirstRecord.map { "\(ReliabilityMetrics.duration($0)) (\(s.finished)회)" } ?? "없음"),
            "가장 많이 멈춘 단계: " + (s.mostStopped.map { "\($0.stage.title) \($0.count)회" } ?? "없음"),
        ]
        let failures = last.failures.map { failure in
            "\(failure.stage.title)·\(failure.reason.title)\(failure.tool.map { "·\($0.provider.name)" } ?? "") \(failure.count)회"
        }
        lines.append("마지막 시도 실패: " + (failures.isEmpty ? "없음" : failures.joined(separator: " · ")))
        return lines
    }
}
