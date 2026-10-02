import Foundation
import SwiftData

/// 프로젝트 「지금 상황」(TRK-63). 에이전트가 `project_status`로 쓰는 짧은 글이고, 최신 `project.status` 이벤트가 현재 상황이다.
/// 모델 필드는 늘리지 않는다(이벤트로만 남긴다).
public enum ProjectStatus {
    /// 글 최대 길이(문자). 넘으면 오류로 알려 다시 쓰게 한다(자르지 않는다).
    public static let characterLimit = 600
    /// 글 최대 줄 수(빈 줄 제외).
    public static let lineLimit = 8
    /// 이보다 오래된 상황은 시작 블록에 「오래됨」으로 표시한다.
    public static let staleAfter: TimeInterval = 7 * 24 * 3600

    public struct Entry: Equatable, Sendable {
        public let text: String
        public let at: Date
        public let provider: AgentProvider?
        public let sessionID: String?

        public func isStale(now: Date) -> Bool { now.timeIntervalSince(at) > ProjectStatus.staleAfter }
    }

    /// 앞뒤 공백을 다듬고 빈 줄을 뺀 글. 비었거나 길면 이유를 담은 오류.
    public static func normalized(_ raw: String) throws -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { throw MCPToolError("text가 비어 있음") }
        guard text.count <= characterLimit, lines.count <= lineLimit else {
            throw MCPToolError("상황은 \(characterLimit)자·\(lineLimit)줄 이내로 줄여 다시 보낸다(지금 \(text.count)자·\(lines.count)줄)")
        }
        return text
    }

    /// 이 프로젝트의 최신 상황. 없으면 nil. `project.status` 이벤트만 읽는다(프로젝트 전체 이벤트를 훑지 않는다).
    public static func latest(for project: Project) -> Entry? {
        events(for: project).max { $0.at < $1.at }.flatMap(entry)
    }

    /// 프로젝트별 최신 상황. `project.status` 이벤트를 한 번만 가져온다(상황판처럼 여러 프로젝트를 한꺼번에 볼 때).
    public static func latestEntries(in context: ModelContext) -> [UUID: Entry] {
        var newest: [UUID: Event] = [:]
        for event in fetch(.projectStatus, in: context) {
            guard let id = event.project?.id else { continue }
            if let old = newest[id], old.at >= event.at { continue }
            newest[id] = event
        }
        return newest.compactMapValues(entry)
    }

    /// 프로젝트별 최신 상황 시각(지표용).
    public static func latestDates(in context: ModelContext) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for event in fetch(EventType.projectStatus, in: context) {
            guard let id = event.project?.id else { continue }
            result[id] = max(result[id] ?? .distantPast, event.at)
        }
        return result
    }

    static func entry(_ event: Event) -> Entry? {
        let p = event.payloadValues
        guard let text = p["summary"]?.stringValue, !text.isEmpty else { return nil }
        return Entry(text: text, at: event.at, provider: p["provider"]?.stringValue.flatMap(AgentProvider.init(rawValue:)),
                     sessionID: p["sessionId"]?.stringValue)
    }

    static func events(for project: Project) -> [Event] {
        guard let context = project.modelContext else {
            return (project.events ?? []).filter { $0.type == .projectStatus }
        }
        return fetch(.projectStatus, in: context).filter { $0.project === project }
    }

    /// 종류 하나의 이벤트(새 종류라 수가 적다).
    static func fetch(_ type: EventType, in context: ModelContext) -> [Event] {
        let raw = type.rawValue
        return (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate<Event> { $0.typeRaw == raw }))) ?? []
    }
}
