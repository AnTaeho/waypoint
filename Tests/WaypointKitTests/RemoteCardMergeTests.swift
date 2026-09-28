import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct RemoteCardMergeTests {
    /// 메인 context에 옛 값이 남은 카드(여기서는 저장하지 않은 옛 값으로 흉내)를 새로 읽은 값으로 맞춘다.
    @Test func copiesNewerCardIntoRegisteredModel() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("t.store")
        let container = try WaypointStore.makeContainer(url: url)
        let main = ModelContext(container)
        let p = makeProject(main)
        let card = p.makeCard(in: main, title: "c", status: .idea, at: t0)
        let other = p.makeCard(in: main, title: "o", status: .idea, at: t0)
        try main.save()

        // iPhone이 옮긴 것처럼 다른 context에서 저장
        let phone = ModelContext(container)
        let remote = try #require(phone.fetch(FetchDescriptor<Card>()).first { $0.title == "c" })
        try CardLifecycle.move(remote, to: .next, at: t0 + minutes(5), in: phone)
        try phone.save()
        // 메인 context가 옛 값을 들고 있는 상태
        card.statusRaw = CardStatus.idea.rawValue
        card.updatedAt = t0

        let fresh = ModelContext(container)
        #expect(try RemoteCardMerge.apply(from: fresh, to: main) == 1)
        #expect(card.status == .next)
        #expect(card.updatedAt == t0 + minutes(5))
        #expect(other.status == .idea)
        // 다시 불러도 바뀔 것이 없다
        #expect(try RemoteCardMerge.apply(from: ModelContext(container), to: main) == 0)
    }

    /// 메인 context가 읽지 않은 카드는 건드리지 않는다(다음에 읽을 때 저장소 값이 온다).
    @Test func skipsUnregisteredCards() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("t.store")
        let container = try WaypointStore.makeContainer(url: url)
        let writer = ModelContext(container)
        let p = makeProject(writer)
        p.makeCard(in: writer, title: "c", status: .idea, at: t0)
        try writer.save()

        let main = ModelContext(container)
        #expect(try RemoteCardMerge.apply(from: ModelContext(container), to: main) == 0)
        #expect(main.hasChanges == false)
    }
}
