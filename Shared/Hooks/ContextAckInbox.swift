import Foundation

/// 훅 스크립트가 블록을 출력했다는 확인(응답 ID)을 받아 두는 메모리 집합(TRK-35).
/// 서버 큐에서 넣고(메인 큐·저장·화면 갱신을 거치지 않는다) 다음 훅을 메인에서 처리할 때 꺼내 확정한다.
/// 앱을 다시 켜면 비어 있다. 그때는 블록이 한 번 더 나갈 뿐이다. 오래된 것부터 버려 크기를 묶는다.
public final class ContextAckInbox: @unchecked Sendable {
    public static let capacity = 1000
    private let lock = NSLock()
    private var ids = Set<String>()
    private var order: [String] = []

    public init() {}

    public func insert(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        guard ids.insert(id).inserted else { return }
        order.append(id)
        if order.count > Self.capacity {
            ids.remove(order.removeFirst())
        }
    }

    /// 있으면 꺼내고 true.
    public func take(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard ids.remove(id) != nil else { return false }
        order.removeAll { $0 == id }
        return true
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return ids.count
    }
}
