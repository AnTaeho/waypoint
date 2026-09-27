import Foundation
import SwiftData

/// 카드 상세에서 사용자가 바꾸는 것. 저장(save)은 호출 쪽에서 한다.
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
}
