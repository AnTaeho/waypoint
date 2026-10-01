import SwiftData

/// 사이드바 선택. 프로젝트는 모델 대신 식별자로 들고 있는다(선택 상태가 모델 수명과 엮이지 않게).
enum SidebarSelection: Hashable {
    case dashboard
    case guidance
    case project(PersistentIdentifier)
}
