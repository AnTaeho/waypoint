import CoreData
import SwiftData
import SwiftUI
import WaypointKit

/// 날짜·제목, 작업중 카드들(프로젝트 순으로 묶임), 방금 기록된 아이디어.
struct PhoneHomeView: View {
    let projects: [Project]
    let ideaCards: [Card]
    let now: Date
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        let groups = DashboardQuery.groups(for: projects, now: now)
        let rows = groups.flatMap { group in group.rows.map { PhoneWorkItem(project: group.project, row: $0) } }
        let liveCount = rows.filter { $0.row.workState == .live }.count
        let ideas = IdeaInbox.recent(ideaCards, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Phone.sectionGap) {
                header(liveCount: liveCount)
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Phone.cardGap) {
                        ForEach(rows) { item in
                            PhoneWorkCard(item: item, now: now)
                        }
                    }
                }
                if !ideas.isEmpty {
                    PhoneIdeaSection(cards: ideas, now: now)
                }
            }
            .padding(.horizontal, Theme.Phone.gutter)
            .padding(.vertical, Theme.Phone.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if DEBUG
        .onChange(of: PhoneDebugLog.summary(projects: projects, rows: rows, ideas: ideas), initial: true) { _, line in
            PhoneDebugLog.print(line)
        }
        .task(id: ideas.map(\.displayID)) {
            // 실측용: 실행 인자 `-WaypointMoveIdea PRB-3`이면 그 카드를 버튼과 같은 길로 「다음 할 일로」 옮긴다.
            guard let target = PhoneDebugLog.pendingMove,
                  let card = ideas.first(where: { $0.displayID == target }) else { return }
            PhoneDebugLog.pendingMove = nil
            PhoneDebugLog.print("move \(target) → next")
            PhoneIdeaAction.move(card, to: .next, in: context)
        }
        #endif
    }

    private func header(liveCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(now.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))))
                    .font(Theme.Phone.date)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                if AppInstance.current.isDev {
                    Text("Dev")
                        .font(Theme.Dev.badgeFont)
                        .foregroundStyle(Theme.Dev.badgeText)
                        .padding(.horizontal, Theme.Dev.badgePaddingH)
                        .padding(.vertical, Theme.Dev.badgePaddingV)
                        .background(Theme.Dev.badgeBg, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
                }
            }
            Text(liveCount > 0 ? "작업중 \(liveCount)" : "진행 중인 작업 없음")
                .font(Theme.Phone.title)
                .foregroundStyle(Theme.text)
        }
    }
}

/// 작업중 목록 한 칸: 프로젝트와 대시보드 줄.
struct PhoneWorkItem: Identifiable {
    let project: Project
    let row: DashboardRow

    var id: String { row.id }
}

#if DEBUG
/// 실측용: 작업중 줄이 바뀐 시각을 콘솔(`devicectl device process launch --console`)에 남긴다.
@MainActor
enum PhoneDebugLog {
    static var pendingMove: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-WaypointMoveIdea"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    /// 「projects=1 ideas=0 rows=1 live:sess·2d66|-」
    static func summary(projects: [Project], rows: [PhoneWorkItem], ideas: [Card]) -> String {
        let rowText = rows.map { "\($0.row.workState.rawValue):\($0.row.card?.displayID ?? SessionFormat.label(for: $0.row.session))" }
        return "projects=\(projects.count) ideas=\(ideas.map(\.displayID)) rows=\(rows.count) \(rowText.joined(separator: ","))"
    }

    /// 가져오기·내보내기 이벤트가 끝날 때마다 한 줄.
    static func cloudKitEvent(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
        let kind = switch event.type {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "other"
        }
        print("cloudkit \(kind) ok=\(event.succeeded) \(event.error.map { "\($0)" } ?? "")")
    }

    static func print(_ line: String) {
        let stamp = Date().formatted(.iso8601.time(includingFractionalSeconds: true))
        Swift.print("[waypoint] \(stamp)Z \(line)")
    }
}
#endif
