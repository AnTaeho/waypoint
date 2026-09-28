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

    /// 저장 폴더를 바꾸는 환경 변수. 훅 스크립트(`waypoint-hook.sh`)와 같은 이름이라 한 값으로 저장소·outbox를 함께 옮긴다.
    /// 확인·디버그용으로 실제 저장소를 건드리지 않고 앱을 띄울 때 쓴다.
    public static let supportDirectoryEnvironmentKey = AppInstance.supportDirectoryEnvironmentKey

    /// 평소용은 ~/Library/Application Support/Waypoint, 개발용은 …/Waypoint-Dev(`AppInstance`).
    /// 환경 변수 `WAYPOINT_SUPPORT_DIR`가 있으면 그 폴더. `create`면 폴더가 없을 때 만든다.
    public static func supportDirectory(create: Bool = true) throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let custom = environment[supportDirectoryEnvironmentKey], !custom.isEmpty {
            base = URL(fileURLWithPath: "/")  // 환경 변수가 있으면 쓰지 않는다
        } else {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create
            )
        }
        let dir = AppInstance.current.supportDirectory(base: base, environment: environment)
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
    ///   - cloudKitContainer: 이 CloudKit 컨테이너의 개인 DB로 미러링한다. nil이면 로컬만(테스트·샘플 기본값).
    ///     메모리 저장소에서는 무시한다.
    public static func makeContainer(
        inMemory: Bool = false, url: URL? = nil, cloudKitContainer: String? = nil
    ) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let storeURL = try url ?? defaultStoreURL()
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: cloudKitDatabase(cloudKitContainer))
        }
        creationLock.lock()
        defer { creationLock.unlock() }
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func cloudKitDatabase(_ container: String?) -> ModelConfiguration.CloudKitDatabase {
        guard let container, !container.isEmpty else { return .none }
        return .private(container)
    }
}
