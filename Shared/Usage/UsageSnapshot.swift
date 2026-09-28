import Foundation

/// Claude 사용량(5시간·7일 창). 상태줄 중계 스크립트(`integration/statusline/waypoint-statusline-tap.sh`)가
/// 저장 폴더에 남기는 `usage.json`을 읽는다. 앱은 이 파일만 읽고 네트워크를 쓰지 않는다.
///
/// 파일 형식: `{"capturedAt":<unix 초>,"rateLimits":{"five_hour":{"used_percentage":42,"resets_at":<unix 초>},"seven_day":{...}}}`
/// 값은 Claude Code가 상태줄에 넘긴 그대로라 형식이 바뀔 수 있어 방어적으로 읽는다.
public struct UsageSnapshot: Equatable, Sendable {

    public struct Window: Equatable, Sendable {
        /// 0–100
        public var usedPercent: Double
        public var resetsAt: Date?

        public init(usedPercent: Double, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }

        /// 초기화 시각이 지났는지. 지났으면 기록된 값은 이전 창의 것이다.
        public func hasReset(at now: Date) -> Bool {
            guard let resetsAt else { return false }
            return resetsAt <= now
        }

        /// 화면에 보일 값(0–100 정수). 초기화 시각이 지났으면 0.
        public func percent(at now: Date) -> Int {
            if hasReset(at: now) { return 0 }
            return Int(min(max(usedPercent, 0), 100).rounded())
        }

        /// 막대 채움 비율(0–1). 초기화 시각이 지났으면 0.
        public func fraction(at now: Date) -> Double {
            if hasReset(at: now) { return 0 }
            return min(max(usedPercent, 0), 100) / 100
        }
    }

    public var fiveHour: Window?
    public var sevenDay: Window?
    public var capturedAt: Date

    public init(fiveHour: Window?, sevenDay: Window?, capturedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.capturedAt = capturedAt
    }

    public static let fileName = "usage.json"

    /// 이보다 오래된 기록은 흐리게 보인다.
    public static let staleAfter: TimeInterval = 30 * 60

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) > Self.staleAfter
    }

    // MARK: 읽기

    /// `usage.json` 내용을 읽는다. 두 창이 모두 없으면 nil.
    /// - Parameter fallbackCapturedAt: `capturedAt`이 없거나 읽을 수 없을 때 쓸 시각(보통 파일 수정 시각). 이것도 없으면 nil.
    public static func parse(_ data: Data, fallbackCapturedAt: Date? = nil) -> UsageSnapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        // 중계 스크립트 형식은 rateLimits 아래, 입력 원본(rate_limits)을 그대로 둔 경우도 받는다.
        let limits = (root["rateLimits"] as? [String: Any]) ?? (root["rate_limits"] as? [String: Any]) ?? root
        let fiveHour = window(limits["five_hour"])
        let sevenDay = window(limits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }
        guard let capturedAt = date(root["capturedAt"]) ?? fallbackCapturedAt else { return nil }
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay, capturedAt: capturedAt)
    }

    /// 파일을 읽는다. 없거나 읽을 수 없으면 nil. `capturedAt`이 없으면 파일 수정 시각을 쓴다.
    public static func load(from url: URL) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return parse(data, fallbackCapturedAt: modified)
    }

    private static func window(_ value: Any?) -> Window? {
        guard let dict = value as? [String: Any], let percent = number(dict["used_percentage"]) else { return nil }
        return Window(usedPercent: percent, resetsAt: date(dict["resets_at"]))
    }

    /// 숫자 또는 숫자 문자열. Bool은 받지 않는다.
    static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite ? d : nil
        }
        if let s = value as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite {
            return d
        }
        return nil
    }

    /// 유닉스 시각(초, 1e12 이상이면 밀리초로 본다) 또는 ISO 8601 문자열.
    static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds >= 1e12 ? seconds / 1000 : seconds)
        }
        guard let s = value as? String else { return nil }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: s)
    }
}
