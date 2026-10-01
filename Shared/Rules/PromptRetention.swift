import Foundation
import SwiftData

/// 사용자 요청 문장 보관 기간(SPEC 5장 「요청 문장 보관」). 기간이 지나면 문장만 지우고 이벤트·시각·세션·카드 연결은 남긴다.
/// - 요청 이벤트(`note`, `kind: user.prompt`): 기록 시각(`at`)부터 30일.
/// - `Session.lastPrompt`: 끝난 세션만, 마지막 요청 시각(`lastPromptAt`, 없으면 `endedAt`)부터 30일.
///   같은 문장의 요청 이벤트와 같은 날 사라진다. 끝나지 않은 세션은 타일 제목이라 그대로 둔다.
public enum PromptRetention {

    /// 보관 기간(일). 되돌리거나 늘리려면 이 값만 바꾼다.
    public static let days = 30
    public static let interval: TimeInterval = TimeInterval(days) * 24 * 60 * 60
    /// 정리 간격. 앱 시작 직후 한 번, 그 뒤 하루에 한 번.
    public static let runInterval: TimeInterval = 24 * 60 * 60

    static let promptKind = "user.prompt"

    /// 이 시각에 기록한 요청 문장을 지울 때가 됐는가.
    public static func isExpired(recordedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(recordedAt) >= interval
    }

    /// 세션의 `lastPrompt`를 지울 때가 됐는가. 끝나지 않은 세션은 false.
    public static func isSessionPromptExpired(endedAt: Date?, lastPromptAt: Date?, now: Date) -> Bool {
        guard let endedAt else { return false }
        return isExpired(recordedAt: lastPromptAt ?? endedAt, now: now)
    }

    /// 정리를 돌릴 때가 됐는가(처음이거나 마지막 정리에서 하루가 지났으면).
    public static func isDue(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= runInterval
    }

    /// 문장이 남은 요청 이벤트인가.
    static func hasPromptText(_ event: Event) -> Bool {
        let p = event.payloadValues
        return p["kind"]?.stringValue == promptKind && !(p["text"]?.stringValue ?? "").isEmpty
    }

    /// 기간이 지난 요청 문장을 지운다. 바꾼 이벤트·세션 수를 돌려준다. 저장은 부르는 쪽이 한다.
    @discardableResult
    public static func apply(in context: ModelContext, now: Date) -> (events: Int, sessions: Int) {
        let cutoff = now.addingTimeInterval(-interval)
        let note = EventType.note.rawValue
        let old = FetchDescriptor<Event>(predicate: #Predicate<Event> { $0.typeRaw == note && $0.at <= cutoff })
        var events = 0
        for event in (try? context.fetch(old)) ?? [] where isExpired(recordedAt: event.at, now: now) && hasPromptText(event) {
            var payload = event.payloadValues
            payload["text"] = nil
            event.payload = EventValue.encode(payload)
            events += 1
        }
        let prompted = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.lastPrompt != nil && $0.endedAt != nil })
        var sessions = 0
        for session in (try? context.fetch(prompted)) ?? []
        where isSessionPromptExpired(endedAt: session.endedAt, lastPromptAt: session.lastPromptAt, now: now) {
            session.lastPrompt = nil
            sessions += 1
        }
        return (events, sessions)
    }
}
