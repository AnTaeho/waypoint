import Foundation
import SwiftData

/// 카드 상세에서 사용자가 바꾸는 것. `setCriterion`은 저장하지 않고, `…AndSave`는 저장까지 한다(실패하면 다시 읽기).
public enum CardEditing {

    /// `note` 이벤트 payload의 `kind` 값: 완료 조건 체크 변경.
    public static let criterionNoteKind = "criterion"

    /// 완료 조건 하나의 체크를 바꾼다. 값이 같거나 범위 밖이면 아무 일도 없고 false.
    /// 바꿨으면 `updatedAt`을 갱신하고 `note` 이벤트(kind=criterion, text, isDone)를 남긴다.
    @discardableResult
    public static func setCriterion(
        _ card: Card, at index: Int, isDone: Bool, date: Date, in context: ModelContext
    ) -> Bool {
        guard card.criteria.indices.contains(index), card.criteria[index].isDone != isDone else { return false }
        var criteria = card.criteria
        criteria[index].isDone = isDone
        // 배열을 통째로 다시 넣어 SwiftData가 변경을 알아채게 한다.
        card.criteria = criteria
        card.updatedAt = date
        Event.record(.note, in: context, card: card, at: date, payload: [
            "kind": .string(criterionNoteKind),
            "text": .string(criteria[index].text),
            "isDone": .bool(isDone),
        ])
        return true
    }
    /// `card_update`로 완료 조건을 통째로 바꿨을 때: 체크가 바뀐 조건(같은 글의 체크 변경, 체크된 채 새로 생긴 조건)마다
    /// `setCriterion`과 같은 `note` 이벤트를 남긴다. 기록과 메모 갱신률(`TrackingCoverage`)에 보이게 한다.
    public static func recordCriteriaChanges(_ card: Card, from old: [Criterion], at date: Date, in context: ModelContext) {
        var before: [String: Bool] = [:]
        for criterion in old where before[criterion.text] == nil { before[criterion.text] = criterion.isDone }
        for criterion in card.criteria {
            let previous = before[criterion.text]
            guard previous != criterion.isDone, previous != nil || criterion.isDone else { continue }
            Event.record(.note, in: context, card: card, at: date, payload: [
                "kind": .string(criterionNoteKind), "text": .string(criterion.text), "isDone": .bool(criterion.isDone),
            ])
        }
    }

    /// 카드 상세의 완료 버튼: 완료로 옮기고 저장한다. 저장했으면 true.
    /// 옮기기·저장이 실패하면 rollback 뒤 저장소 값으로 다시 읽는다.
    @discardableResult
    public static func completeAndSave(
        _ card: Card, at date: Date, in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        do {
            try ContextReload.commit(context, save: save) {
                try CardLifecycle.move(card, to: .done, at: date, in: context)
            }
            return true
        } catch {
            return false
        }
    }

    /// 완료 조건 체크를 바꾸고 저장한다. 바꿀 것이 없으면(`setCriterion`이 false) 저장하지 않고 false.
    /// 저장이 실패하면 rollback 뒤 저장소 값으로 다시 읽고 false.
    @discardableResult
    public static func setCriterionAndSave(
        _ card: Card, at index: Int, isDone: Bool, date: Date, in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        guard card.criteria.indices.contains(index), card.criteria[index].isDone != isDone else { return false }
        do {
            try ContextReload.commit(context, save: save) {
                setCriterion(card, at: index, isDone: isDone, date: date, in: context)
            }
            return true
        } catch {
            return false
        }
    }
}
