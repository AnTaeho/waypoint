import Foundation

/// 이 기기의 기록 신뢰성 지표(TRK-11, docs/RELIABILITY.md). 저장 폴더 `metrics.json`에만 두고 CloudKit에 올리지 않는다.
/// 숫자와 시각만 담는다. 프로젝트·경로·세션 ID·대화가 들어갈 문자열 필드가 없다(`ReliabilityMetricsTests`가 고정).
public struct ReliabilityMetrics: Codable, Equatable, Sendable {
    /// 수신 지연 표본 수(최근 것만). 측정 스크립트의 한 번 버스트(500건)보다 크게.
    public static let receiptLimit = 1000
    public static let resumeLimit = 100

    /// 지표를 모으기 시작한 시각
    public var since: Date
    /// 실시간 훅 한 건의 수신(연결 수락) → 저장 끝(밀리초). 오래된 것부터.
    public var saveMs: [Double] = []
    /// 수신 → 화면 반영 알림(밀리초). 저장 뒤 데이터 변경을 알리고 메인 큐가 한 번 돈 시각.
    public var displayMs: [Double] = []
    /// 재개 문맥을 처음 복사한 시각 → 그 카드에 새 세션이 연결된 시각(초)
    public var resumeSeconds: [Double] = []
    public var failures = Failures()
    public var recovery = Recovery()

    public struct Failures: Codable, Equatable, Sendable {
        /// 로컬 서버를 열지 못함
        public var server = 0
        /// 훅 본문·이벤트 형식 오류
        public var invalidInput = 0
        /// 실시간 훅 저장 실패
        public var saveFailed = 0
        public init() {}
        public var total: Int { server + invalidInput + saveFailed }
    }

    public struct Recovery: Codable, Equatable, Sendable {
        /// outbox에서 흡수한 줄
        public var absorbed = 0
        /// 저장 실패로 outbox 줄을 남겨 둔 횟수(다음 점검에서 다시 흡수)
        public var preserved = 0
        /// 읽을 수 없어 격리한 줄
        public var quarantined = 0
        /// `SessionEnd` 없이 끝나 정리한 세션
        public var sessionsClosed = 0
        public init() {}
        public var isEmpty: Bool { absorbed + preserved + quarantined + sessionsClosed == 0 }
    }

    public init(since: Date = Date()) { self.since = since }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        since = try c.decode(Date.self, forKey: .since)
        saveMs = try c.decodeIfPresent([Double].self, forKey: .saveMs) ?? []
        displayMs = try c.decodeIfPresent([Double].self, forKey: .displayMs) ?? []
        resumeSeconds = try c.decodeIfPresent([Double].self, forKey: .resumeSeconds) ?? []
        failures = try c.decodeIfPresent(Failures.self, forKey: .failures) ?? Failures()
        recovery = try c.decodeIfPresent(Recovery.self, forKey: .recovery) ?? Recovery()
    }

    /// 실시간 훅 한 건. 시각이 거꾸로면(시계 조정) 0으로.
    public mutating func recordReceipt(receivedAt: Date, savedAt: Date, shownAt: Date) {
        Self.append(max(0, savedAt.timeIntervalSince(receivedAt)) * 1000, to: &saveMs, limit: Self.receiptLimit)
        Self.append(max(0, shownAt.timeIntervalSince(receivedAt)) * 1000, to: &displayMs, limit: Self.receiptLimit)
    }

    public mutating func recordResume(seconds: TimeInterval) {
        Self.append(max(0, seconds), to: &resumeSeconds, limit: Self.resumeLimit)
    }

    public mutating func recordAbsorb(_ result: Outbox.DrainResult) {
        recovery.absorbed += result.processed
        recovery.quarantined += result.skipped
        if result.retryPending { recovery.preserved += 1 }
    }

    private static func append(_ value: Double, to values: inout [Double], limit: Int) {
        values.append(value)
        if values.count > limit { values.removeFirst(values.count - limit) }
    }

    // MARK: - 요약

    public struct Summary: Equatable, Sendable {
        public let count: Int
        public let p50: Double
        public let p95: Double
        public let max: Double
    }

    /// 최근 순위 백분위(nearest-rank): 정렬해서 `ceil(p·n)`번째. 표본이 없으면 nil.
    public static func summary(_ values: [Double]) -> Summary? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        func rank(_ p: Double) -> Double { sorted[min(sorted.count - 1, max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1))] }
        return Summary(count: sorted.count, p50: rank(0.5), p95: rank(0.95), max: sorted[sorted.count - 1])
    }

    /// 짧은 시간 표시: 10초 미만은 소수 둘째 자리까지, 2분 미만은 초, 그 이상은 분·초.
    public static func duration(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "%.2f초", seconds) }
        if seconds < 120 { return "\(Int(seconds.rounded()))초" }
        let total = Int(seconds.rounded())
        return total % 60 == 0 ? "\(total / 60)분" : "\(total / 60)분 \(total % 60)초"
    }

    static func milliseconds(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f ms", value) : "\(Int(value.rounded())) ms"
    }

    /// 진단 내보내기 줄. 숫자와 시각만.
    public func diagnosticLines() -> [String] {
        func latency(_ title: String, _ values: [Double]) -> String {
            guard let s = Self.summary(values) else { return "\(title): 표본 없음" }
            return "\(title): \(s.count)건 · 중앙값 \(Self.milliseconds(s.p50)) · p95 \(Self.milliseconds(s.p95)) · 최대 \(Self.milliseconds(s.max))"
        }
        let resume = Self.summary(resumeSeconds).map {
            "재개 시간: \($0.count)회 · 중앙값 \(Self.duration($0.p50)) · 최대 \(Self.duration($0.max))"
        } ?? "재개 시간: 표본 없음"
        return [
            "기록 지표 (\(since.ISO8601Format()) 부터)",
            latency("수신→저장", saveMs), latency("수신→화면", displayMs), resume,
            "연동 실패: 서버 시작 \(failures.server) · 형식 오류 \(failures.invalidInput) · 저장 실패 \(failures.saveFailed)",
            "복구: 미처리 기록 흡수 \(recovery.absorbed) · 보존 \(recovery.preserved) · 격리 \(recovery.quarantined) · 세션 정리 \(recovery.sessionsClosed)",
        ]
    }
}
