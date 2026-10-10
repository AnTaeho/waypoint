import Foundation
import SwiftData

/// 끝난 세션의 마지막 요청 문장(`Session.lastPrompt`) 보관(SPEC 5장 「기록 보관」). 요청 이벤트는 `RecordRetention`이 지운다.
/// 마지막 요청 시각(`lastPromptAt`, 없으면 `endedAt`)부터 잰다. 끝나지 않은 세션은 타일 제목이라 그대로 둔다.
public enum PromptRetention {

    /// 보관 기간(일). 기록 보관 기간과 같다.
    public static let days = RecordRetention.days
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

    /// 기간이 지난 끝난 세션의 요청 문장을 지운다. 바꾼 세션 수를 돌려준다. 저장은 부르는 쪽이 한다.
    @discardableResult
    public static func apply(in context: ModelContext, now: Date) -> Int {
        let prompted = FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.lastPrompt != nil && $0.endedAt != nil })
        var sessions = 0
        for session in (try? context.fetch(prompted)) ?? []
        where isSessionPromptExpired(endedAt: session.endedAt, lastPromptAt: session.lastPromptAt, now: now) {
            session.lastPrompt = nil
            sessions += 1
        }
        return sessions
    }
}
