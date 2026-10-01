import SwiftUI
import WaypointKit

struct ActivitySessionSection: View {
    let group: ActivitySessionGroup
    let project: Project
    let now: Date
    @State private var expanded: Bool

    init(group: ActivitySessionGroup, project: Project, now: Date, initiallyExpanded: Bool) {
        self.group = group; self.project = project; self.now = now
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(group.entries) { entry in ActivityEventRow(entry: entry) }
            }.padding(.top, Theme.Spacing.l)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title).font(Theme.bodyStrong).foregroundStyle(Theme.text).lineLimit(2)
                    Spacer(minLength: Theme.Spacing.m)
                    Text(group.at.formatted(date: .omitted, time: .shortened))
                        .font(Theme.monoCaption).foregroundStyle(Theme.textMuted)
                }
                Text(metadata).font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
                Text(group.summary).font(Theme.captionLarge).foregroundStyle(Theme.textMuted)
            }
        }
        .tint(Theme.textMuted)
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.panel).strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder) }
    }

    private var metadata: String {
        guard let session = group.session else { return "세션 정보 없는 카드 변경·메모" }
        var parts = [session.provider.name, SessionFormat.label(kind: session.kind, id: session.sourceID, agentName: session.agentName)]
        if session.project?.id == project.id, Calendar.current.isDate(group.at, inSameDayAs: now) {
            parts.append(SessionFormat.activityText(session, now: now))
        }
        return parts.joined(separator: " · ")
    }
}
