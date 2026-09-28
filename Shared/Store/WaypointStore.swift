import Foundation
import SwiftData

public enum WaypointStore {
    public static let schema = Schema([
        Project.self,
        Card.self,
        Session.self,
        CardSession.self,
        Event.self,
        GuideDoc.self,
        GuideVersion.self,
    ])

    /// ~/Library/Application Support/Waypoint. `create`면 폴더가 없을 때 만든다.
    public static func supportDirectory(create: Bool = true) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create
        )
        let dir = base.appendingPathComponent("Waypoint", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 실제 데이터: .../Waypoint/Waypoint.store
    public static func defaultStoreURL(create: Bool = true) throws -> URL {
        try supportDirectory(create: create).appendingPathComponent("Waypoint.store")
    }

    /// 샘플 모드: .../Waypoint/Sample.store
    public static func sampleStoreURL(create: Bool = true) throws -> URL {
        try supportDirectory(create: create).appendingPathComponent("Sample.store")
    }

    /// 컨테이너 생성을 한 번에 하나씩. 여러 컨테이너가 같은 `schema`로 동시에 저장소를 열면
    /// Core Data가 트리거 SQL을 만들며 공유 사전을 함께 고쳐 signal 11로 죽는다(병렬 테스트에서 재현).
    private static let creationLock = NSLock()

    /// - Parameters:
    ///   - inMemory: true면 파일을 쓰지 않는다(url 무시).
    ///   - url: 저장 파일. nil이면 `defaultStoreURL()`.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let storeURL = try url ?? defaultStoreURL()
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        }
        creationLock.lock()
        defer { creationLock.unlock() }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
