import Foundation
import SwiftData

/// context가 이미 올려 둔 프로젝트·카드·세션·연결을 저장소 값으로 다시 맞춘다.
///
/// SwiftData `rollback()`은 메모리의 값과 관계를 되돌리지 않고, 다른 context가 저장한 변경도 이미 올라온 객체에
/// 저절로 들어오지 않는다. 그 객체를 그대로 저장하면 옛 값이 저장소를 덮는다(2026-10-01 실측). 같은 종류를 모두
/// 다시 가져오면 돌려받은 객체가 저장소 값과 관계로 바뀐다(`ContextReloadTests`가 이 동작을 고정한다).
/// 한계: 돌려받은 객체만 바뀌고, 저장하지 않은 변경이 있는 객체는 바뀌지 않는다. 그래서 부르기 전에 context를
/// 저장하거나 rollback해 둔다. 기록(`Event`)은 훅 경로에서 새로 넣기만 하므로 다시 가져오지 않는다.
public enum ContextReload {
    public static func apply(_ context: ModelContext) {
        _ = try? context.fetch(FetchDescriptor<Project>())
        _ = try? context.fetch(FetchDescriptor<Card>())
        _ = try? context.fetch(FetchDescriptor<Session>())
        _ = try? context.fetch(FetchDescriptor<CardSession>())
    }
}
