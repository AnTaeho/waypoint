import CoreData
import SwiftData
import SwiftUI
import WaypointKit

/// iOS 루트: 작업중 목록과 방금 기록된 아이디어 한 화면. 카드를 누르면 상세.
///
/// CloudKit에서 가져온 변경은 새로 생긴 것만 화면에 뜨고, 이미 읽은 객체(세션 `endedAt`·`lastSeenAt` 등)는
/// 메인 context에 옛 값으로 남는다(2026-09 iOS 26 실측). 가져오기가 끝날 때마다 새 context로 바꿔 다시 읽는다.
struct RootView: View {
    @Environment(\.modelContext) private var baseContext
    @State private var context: ModelContext?
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            PhoneHomeQueryView()
                .id(generation)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Card.self) { card in
                    PhoneCardDetail(card: card)
                }
        }
        .modelContext(context ?? baseContext)
        .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)) { note in
            #if DEBUG
            PhoneDebugLog.cloudKitEvent(note)
            #endif
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
                event.type == .import, event.endDate != nil, event.succeeded
            else { return }
            context = ModelContext(baseContext.container)
            generation += 1
        }
    }
}

/// 프로젝트·아이디어 카드를 읽어 시각마다 그린다.
struct PhoneHomeQueryView: View {
    @Query(filter: #Predicate<Project> { $0.archivedAt == nil }, sort: \Project.name)
    private var projects: [Project]
    /// 분류 전 아이디어. 최근 것만 고르는 일은 `IdeaInbox`.
    @Query(filter: #Predicate<Card> { $0.statusRaw == "idea" }, sort: \Card.createdAt, order: .reverse)
    private var ideaCards: [Card]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            PhoneHomeView(projects: projects, ideaCards: ideaCards, now: timeline.date)
        }
        .background(Theme.bg)
    }
}
