import Foundation
import SwiftData

/// CloudKit 가져오기(iPhone에서 옮긴 카드)를 Mac 메인 context에 들인다.
///
/// 가져오기는 저장소만 고치고, 메인 context가 이미 읽어 둔 객체는 옛 값을 그대로 든다. 다시 가져와도(fetch)
/// 새로 고쳐지지 않고, 그 객체를 저장하면 옛 값이 저장소를 통째로 덮어쓴다(2026-09-28 실측).
/// SwiftData에는 객체를 새로 읽는 API가 없어, 새 context로 읽은 값을 이미 올라온 같은 카드에 옮겨 적는다.
/// iPhone이 고치는 것은 카드뿐이라(아이디어 분류) 카드만 맞춘다.
public enum RemoteCardMerge {
    /// `fresh`에서 읽은 카드 중 `target`에 이미 올라와 있고 `updatedAt`이 더 늦은 것의 값을 `target` 쪽에 옮긴다.
    /// 옮긴 카드 수. 저장은 호출 쪽에서 한다.
    @discardableResult
    public static func apply(from fresh: ModelContext, to target: ModelContext) throws -> Int {
        var count = 0
        for card in try fresh.fetch(FetchDescriptor<Card>()) {
            guard let local: Card = target.registeredModel(for: card.persistentModelID),
                  card.updatedAt > local.updatedAt
            else { continue }
            copy(card, into: local)
            count += 1
        }
        return count
    }

    static func copy(_ source: Card, into local: Card) {
        local.title = source.title
        local.body = source.body
        local.kindRaw = source.kindRaw
        local.statusRaw = source.statusRaw
        local.criteria = source.criteria
        local.nextSessionNote = source.nextSessionNote
        local.statusBeforeActive = source.statusBeforeActive
        local.doneAt = source.doneAt
        local.updatedAt = source.updatedAt
    }
}
