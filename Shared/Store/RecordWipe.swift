import Foundation
import SwiftData

/// 모든 기록 지우기(TRK-47). 지우기 전에 열린 저장소를 `beforeDelete`로 백업하고, 백업이 실패하면 지우지 않는다.
///
/// 한 행씩 지운다(`ModelContext.delete(model:)` 같은 일괄 삭제를 쓰지 않는다): iCloud로 이어진 저장소에서
/// 다른 기기(iPhone)에도 지운 것이 건너가게 하려고 보통 저장 경로로 지운다.
/// 저장소 밖 파일(백업·지표·연결 설정)과 설정 값은 건드리지 않는다.
public enum RecordWipe {

    public struct Counts: Equatable, Sendable {
        public var projects = 0
        public var cards = 0
        public var sessions = 0
        public var events = 0
        public var guideDocs = 0

        public init(projects: Int = 0, cards: Int = 0, sessions: Int = 0, events: Int = 0, guideDocs: Int = 0) {
            self.projects = projects
            self.cards = cards
            self.sessions = sessions
            self.events = events
            self.guideDocs = guideDocs
        }

        public var isEmpty: Bool { self == Counts() }
    }

    /// 지금 저장소에 있는 수(확인 대화상자용).
    public static func counts(in context: ModelContext) throws -> Counts {
        Counts(
            projects: try context.fetchCount(FetchDescriptor<Project>()),
            cards: try context.fetchCount(FetchDescriptor<Card>()),
            sessions: try context.fetchCount(FetchDescriptor<Session>()),
            events: try context.fetchCount(FetchDescriptor<Event>()),
            guideDocs: try context.fetchCount(FetchDescriptor<GuideDoc>())
        )
    }

    /// 모든 모델 행을 지우고 저장한다. 지운 수를 돌려준다. 저장이 실패하면 되돌리고 던진다.
    @discardableResult
    public static func deleteAll(in context: ModelContext) throws -> Counts {
        let before = try counts(in: context)
        // 잎에서 뿌리 쪽으로. 관계 규칙(cascade·nullify)과 상관없이 프로젝트에 안 붙은 행까지 모두 지운다.
        try delete(Event.self, in: context)
        try delete(CardSession.self, in: context)
        try delete(GuideVersion.self, in: context)
        try delete(GuideDoc.self, in: context)
        try delete(Session.self, in: context)
        try delete(Card.self, in: context)
        try delete(Project.self, in: context)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return before
    }

    /// 다른 백업이 도는 중이라 지우기 전 백업을 뜨지 못했다.
    public struct BackupBusy: Error {}

    /// 열린 저장소를 백업한 뒤 지운다. 백업이 실패하거나 뜨지 못하면(nil) 아무것도 지우지 않고 던진다.
    /// 백업이 지금 내용을 담도록 먼저 저장한다.
    /// - Parameter backUp: 앱은 `StoreDailyBackup.runNow(reason: .beforeDelete)`(다른 백업과 겹치지 않게).
    public static func backUpAndDeleteAll(
        in context: ModelContext, backUp: () throws -> StoreBackup.Entry?
    ) throws -> (backup: StoreBackup.Entry, deleted: Counts) {
        if context.hasChanges { try context.save() }
        guard let entry = try backUp() else { throw BackupBusy() }
        let deleted = try deleteAll(in: context)
        return (entry, deleted)
    }

    private static func delete<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}
