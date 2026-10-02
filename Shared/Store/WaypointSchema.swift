import Foundation
import SwiftData

/// 저장 형식 1판(TRK-46). 모델 정의는 `Shared/Models`의 클래스를 그대로 쓴다.
/// 이 판을 고정해 두면 다음 판을 더할 때 SwiftData가 어느 판에서 어느 판으로 옮기는지 안다.
///
/// 다음 판을 더하는 절차는 docs/SPEC.md 「저장소 백업·복구」.
public enum WaypointSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Project.self, Card.self, Session.self, CardSession.self, Event.self, GuideDoc.self, GuideVersion.self]
    }
}

/// 판 사이 옮기기. 지금은 판이 하나라 단계가 없다.
public enum WaypointMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [WaypointSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public extension WaypointStore {
    /// 지금 앱이 쓰는 판. 백업 기록(`info.json`)과 지난번 연 판(`store-version.json`)에 남긴다.
    static var currentSchemaVersion: String {
        let version = WaypointSchemaV1.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }
}
