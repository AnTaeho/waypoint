import Foundation
import SwiftData

/// 같은 파일 작업 중(TRK-17)을 에이전트가 자주 부르는 도구 응답에 `overlaps`로 붙인다. 훅 출력은 늘리지 않는다.
extension MCPTools {

    /// 어느 세션의 눈으로 겹침을 볼지. `sessionId`를 주면 그 세션, 아니면 카드에 붙어 있는 끝나지 않은 세션.
    /// `project_status`는 `sessionId`가 있을 때만. 메인 세션과 그 서브에이전트가 함께 있으면 메인 세션만(단위가 같다).
    func overlapSessions(_ tool: String, _ args: JSONValue) throws -> [Session] {
        let date = now()
        var sessions: [Session]
        if let id = optionalString(args, "sessionId"), let session = fetchSession(id) {
            sessions = [session]
        } else if tool != "project_status", let card = try? resolveCard(args) {
            sessions = card.openCardSessions.compactMap(\.session)
        } else {
            sessions = []
        }
        sessions = sessions.filter {
            $0.endedAt == nil && SessionRules.state(of: $0, now: date, stallTimeout: stallTimeout) != .ended
        }
        let ids = Set(sessions.map(\.id))
        var seen = Set<String>()
        return sessions.filter { session in
            let root = WorkOverlap.root(of: session)
            guard root === session || !ids.contains(root.id) else { return false }
            return seen.insert(session.id).inserted
        }
    }

    /// 결과가 객체이고 알릴 겹침이 있으면 `overlaps`를 붙인다. 같은 상대·같은 파일 집합은 한 번만, 새 파일이 겹치면 다시.
    func withOverlaps(_ result: JSONValue, sessions: [Session]) -> JSONValue {
        guard case .object(var json) = result, !sessions.isEmpty else { return result }
        let date = now()
        var items: [JSONValue] = []
        var indexes: [ObjectIdentifier: WorkOverlap.Index] = [:]
        for session in sessions {
            guard let project = session.project else { continue }
            let index = indexes[ObjectIdentifier(project)]
                ?? WorkOverlap.index(for: project, now: date, stallTimeout: stallTimeout)
            indexes[ObjectIdentifier(project)] = index
            for overlap in index.overlaps(for: session) {
                let key = "\(session.id)|\(overlap.other.id)"
                let decision = WorkOverlap.shouldReport(overlap.files, reported: reportedOverlaps[key] ?? [])
                guard decision.report else { continue }
                reportedOverlaps[key] = decision.reported
                items.append(overlapJSON(overlap))
            }
        }
        guard !items.isEmpty else { return result }
        json["overlaps"] = .array(items)
        return .object(json)
    }

    func overlapJSON(_ overlap: WorkOverlap.Overlap) -> JSONValue {
        var json: [String: JSONValue] = [
            "sessionId": .string(UnfiledWork.shortID(overlap.other)),
            "provider": .string(overlap.other.provider.rawValue),
            "files": .array(overlap.files.prefix(WorkOverlap.agentFileLimit).map { .string($0) }),
            "fileCount": JSONValue(overlap.files.count),
        ]
        if !overlap.cards.isEmpty { json["cards"] = .array(overlap.cards.map { .string($0.displayID) }) }
        return .object(json)
    }
}
