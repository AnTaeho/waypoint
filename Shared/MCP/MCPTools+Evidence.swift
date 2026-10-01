import Foundation
import SwiftData

/// `card_evidence`: 에이전트가 보고한 검증 근거(SPEC 7장).
extension MCPTools {

    /// `detail` 최대 길이(문자).
    public static let evidenceDetailLimit = 200

    func cardEvidence(_ args: JSONValue) throws -> JSONValue {
        let card = try resolveCard(args)
        let command = try requiredString(args, "command").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw MCPToolError("command가 비어 있음") }
        guard let rawOutcome = optionalString(args, "outcome"),
              let outcome = CheckOutcome(rawValue: rawOutcome), outcome != .unknown
        else { throw MCPToolError("outcome은 pass·fail·skipped 중 하나") }

        var index: Int?
        if let raw = args["criterion"], !raw.isNull {
            guard let value = raw.numberValue, let number = Int(exactly: value) else {
                throw MCPToolError("criterion은 정수(1부터)")
            }
            guard !card.criteria.isEmpty else { throw MCPToolError("완료 조건이 없는 카드: criterion을 빼고 보낸다") }
            guard (1...card.criteria.count).contains(number) else {
                throw MCPToolError("criterion은 1–\(card.criteria.count)")
            }
            index = number - 1
        }
        let session = optionalString(args, "sessionId").flatMap(fetchSession)
        let trimmedDetail = optionalString(args, "detail")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = trimmedDetail.isEmpty ? nil : String(trimmedDetail.prefix(Self.evidenceDetailLimit))
        let record = CheckRecord(
            at: now(), command: VerificationCommand.display(command), outcome: outcome, source: .agent,
            criterion: index, criterionText: index.map { card.criteria[$0].text }, detail: detail,
            provider: session?.provider
        )
        CardEvidence.record(record, card: card, session: session, in: context)

        var json: [String: JSONValue] = [
            "id": .string(card.displayID), "outcome": .string(outcome.rawValue), "source": .string("agent"),
        ]
        if let index {
            let evidence = CardEvidence.criteria(for: card)[index]
            json["criterion"] = JSONValue(index + 1)
            json["state"] = .string(evidence.state.rawValue)
            json["confirmed"] = .bool(evidence.source == .hook)
        }
        return .object(json)
    }
}
