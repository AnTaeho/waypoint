import Foundation
import SwiftData
import WaypointKit

/// 첫 실행 자동 표시와, 손 없이 화면을 확인할 때의 Debug 전용 실행 인자.
/// - `-WaypointOnboarding tools|install|apply|project|receive`: 그 단계로 온보딩을 연다.
///   `apply`는 연결 계획을 바로 적용한다. `WAYPOINT_INTEGRATION_HOME`(확인용 홈)이 있을 때만.
///   `-WaypointOnboardingFolder`와 함께 주면 적용 뒤 첫 기록 단계로 넘어간다.
/// - `-WaypointOnboardingFolder <경로>`: 프로젝트 단계에서 그 폴더를 고른 것으로 본다. 등록 안 된 폴더면
///   확인 창 없이 바로 등록한다(확인용 저장 폴더 `WAYPOINT_SUPPORT_DIR`와 함께 쓴다).
@MainActor
enum OnboardingLaunch {
    /// 서비스가 시작된 뒤 한 번 부른다.
    static func start(_ model: OnboardingModel, container: ModelContainer) {
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: "WaypointOnboarding") {
            open(forced, model: model, container: container)
            return
        }
        #endif
        let context = container.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        if OnboardingProgress.shouldAutoPresent(projectCount: count, completed: OnboardingModel.completed) {
            model.present()
        }
    }

    #if DEBUG
    private static func open(_ forced: String, model: OnboardingModel, container: ModelContainer) {
        let step: OnboardingProgress.Step = switch forced {
        case "install", "apply": .install
        case "project": .project
        case "receive": .receive
        default: .tools
        }
        model.present(at: step)
        if let folder = UserDefaults.standard.string(forKey: "WaypointOnboardingFolder") {
            register(folder, model: model, context: container.mainContext)
        }
        guard forced == "apply", IntegrationEnvironment.isOverridden else { return }
        model.prepareInstall()
        let folder = UserDefaults.standard.string(forKey: "WaypointOnboardingFolder")
        Task {
            await model.install?.apply()
            // 폴더도 줬으면 한 번에 첫 기록 단계까지(깨끗한 환경 첫 설정 실측, TRK-45)
            if folder != nil { model.requested = .receive }
        }
    }

    private static func register(_ folder: String, model: OnboardingModel, context: ModelContext) {
        let root = ProjectMatcher.normalize(folder)
        if ProjectRegistry.project(atRoot: root, in: context) == nil {
            let draft = ProjectDraft.folder(root, taken: ProjectRegistry.takenKeys(in: context))
            _ = try? ProjectRegistry.register(draft, at: Date(), context: context)
        }
        model.choose(folder: URL(fileURLWithPath: root), context: context)
    }
    #endif
}
