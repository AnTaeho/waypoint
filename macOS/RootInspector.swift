import SwiftData
import SwiftUI
import WaypointKit

/// 인스펙터 내용 고르기: 카드 상세가 맨 위면 카드 정보, 지침 문서 화면이면 문서 정보, 아니면 최근 기록.
struct RootInspector: View {
    let projectID: PersistentIdentifier?
    let card: Card?
    /// 지침 문서 화면일 때만 값이 있다(nil이면 그 프로젝트의 첫 문서).
    let guideDocID: PersistentIdentifier?
    let open: (Card) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        if let card {
            CardInspector(card: card, open: open)
        } else if let doc = guideDoc {
            GuideInspector(doc: doc)
        } else {
            RecentEventsInspector(projectID: projectID)
        }
    }

    private var guideDoc: GuideDoc? {
        // 등록 해제된 문서를 식별자로 바로 꺼내지 않게 프로젝트의 문서 목록에서 찾는다.
        guard let guideDocID, let projectID, let project = context.model(for: projectID) as? Project else { return nil }
        return (project.guideDocs ?? []).first { $0.persistentModelID == guideDocID }
    }
}
