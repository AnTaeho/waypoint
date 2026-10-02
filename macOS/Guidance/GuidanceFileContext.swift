import SwiftUI
import WaypointKit

/// 지침 화면이 프로젝트 밖 파일을 쓸 때 쓰는 것: 백업 자리, Codex 실행 파일, 쓴 뒤 할 일, 지움 알림.
struct GuidanceFileContext: Sendable {
    var backups: GuidanceBackupStore?
    /// 규칙 파일 검사에 쓸 `codex`. 없으면 자체 검사.
    var codex: String?
    /// 파일을 쓴 뒤(목록 다시 모으기)
    var didWrite: @MainActor @Sendable () -> Void = {}
    /// 지운 뒤 화면 아래 알림. 기억 파일을 지우면 출처가 목록에서 빠지므로 지침 화면이 들고 있는다.
    var showUndo: @MainActor @Sendable (GuidanceFileWrite.ChangeSet) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var guidanceFiles = GuidanceFileContext()
}

/// 파일 쓰기를 메인 스레드 밖에서(규칙 검사는 Codex를 띄워 3초까지 걸릴 수 있다).
enum GuidanceFileRunner {
    static func apply(_ changes: [GuidanceFileWrite.Change], context: GuidanceFileContext,
                      reason: GuidanceBackupStore.Reason, checkRules: Bool) async throws {
        guard let backups = context.backups else { throw GuidanceFileWrite.Failure.notWritable }
        let codex = context.codex
        try await Task.detached(priority: .userInitiated) {
            try GuidanceFileWrite.apply(
                changes, backups: backups, reason: reason, at: Date(),
                checkRules: checkRules ? { CommandRulesCheck.check($0, codex: codex) } : nil
            )
        }.value
    }

    /// 화면에 보일 짧은 이유.
    static func message(_ error: Error) -> String {
        switch error {
        case GuidanceFileWrite.Failure.changed: "바뀜"
        case GuidanceFileWrite.Failure.notWritable: "쓸 수 없는 파일"
        case GuidanceFileWrite.Failure.invalidRules(let outcome): "저장 안 함 · \(outcome.message ?? "규칙 오류")"
        case GuideItemEdit.Failure.staleItem: "항목이 바뀜"
        default: "저장 못 함 · \(error.localizedDescription)"
        }
    }
}

/// 백업 사본을 남긴 까닭 이름.
enum GuidanceBackupFormat {
    static func reasonName(_ reason: GuidanceBackupStore.Reason) -> String {
        switch reason {
        case .edit: "고치기 전"
        case .delete: "지우기 전"
        case .restore: "복원 전"
        case .undo: "되돌리기 전"
        }
    }
}
