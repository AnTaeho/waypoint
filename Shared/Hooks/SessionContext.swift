import Foundation

/// `SessionStart` 응답 본문(대화 컨텍스트에 주입되는 짧은 텍스트). Claude가 읽는 글이라 화면 문구 규칙과 별개다.
public enum SessionContext {

    public static let nextLimit = 5

    /// 등록되지 않은 폴더에서 연 세션에 주는 한 줄.
    public static let unregistered = "Waypoint: 이 폴더는 Waypoint에 없음. `/tracker init`으로 등록할 수 있음."

    /// 미등록 시작 폴더에서도 실제 ID를 전달해 작업 대상 프로젝트를 명시적으로 연결할 수 있다.
    public static func awaitingProject(_ input: HookInput) -> String {
        [unregistered, "sessionId: \(input.sessionID)", "provider: \(input.provider.rawValue)",
         "작업 대상 폴더가 정해지면 project_resolve로 확인하고 session_bind로 연결한 뒤 tracker 스킬을 따른다."]
            .joined(separator: "\n")
    }

    /// 블록 마지막 줄. 스킬이 이 블록을 보고 켜지게 한다.
    public static let skillHint = "작업을 시작·전환하거나 한 단위를 끝낼 때마다, 나중에 할 일을 들으면 tracker 스킬을 따른다."

    /// `Waypoint:`로 시작하는 블록: 프로젝트 키·이름, `sessionId`, 지금 상황(최신 `project_status`), 다음 할 일 상위 5개,
    /// 이 프로젝트의 다른 작업중 카드, 직전 세션 메모(가장 최근에 `card_handoff`한 카드 하나), 정리 안 된 작업(최대 3개).
    /// 형식은 `integration/skills/tracker/SKILL.md`와 맞춘다.
    public static func text(
        project: Project,
        session: Session,
        now: Date,
        stallTimeout: TimeInterval = SessionRules.defaultStallTimeout
    ) -> String {
        let cards = (project.cards ?? []).filter { $0.status != .archived }
        var lines = [
            "Waypoint: \(project.key) (\(project.name))",
            "sessionId: \(session.id)",
        ]
        if session.provider == .codex { lines.append("provider: codex") }

        if let status = ProjectStatus.latest(for: project) {
            lines.append("지금 상황 (\(statusHeader(status, now: now))):")
            lines += status.text.split(separator: "\n", omittingEmptySubsequences: true).map { "  \($0)" }
        }

        let next = cards.filter { $0.status == .next }.sorted { $0.number < $1.number }.prefix(nextLimit)
        if !next.isEmpty {
            lines.append("다음 할 일:")
            lines += next.map { "- \($0.displayID) \($0.title)" }
        }

        // 카드 없는 세션 줄은 알려 줄 작업이 없으므로 뺀다.
        let others = DashboardQuery.rows(for: project, now: now, stallTimeout: stallTimeout)
            .filter { $0.session !== session && $0.session.parent !== session }
            .compactMap { row in row.card.map { (card: $0, row: row) } }
        if !others.isEmpty {
            lines.append("다른 세션에서 작업중:")
            lines += others.map { card, row in
                let stalled = ", \(SessionActivityRules.activity(row.session, now: now, timeout: stallTimeout).title)"
                return "- \(card.displayID) \(card.title) (\(SessionFormat.label(for: row.session))\(stalled))"
            }
        }

        if let card = latestHandoff(in: cards), let note = card.nextSessionNote {
            lines.append("직전 세션 메모 (\(card.displayID) \(card.title)):")
            lines += note.split(separator: "\n", omittingEmptySubsequences: true).map { "  \($0)" }
        }

        let unfiled = UnfiledWork.items(for: project, now: now, limit: UnfiledWork.blockLimit, excluding: session)
        if !unfiled.isEmpty {
            lines.append("정리 안 된 작업:")
            lines += unfiled.prefix(UnfiledWork.blockLimit).map { UnfiledWork.line($0, now: now) }
            if unfiled.count > UnfiledWork.blockLimit { lines.append("- 외 \(unfiled.count - UnfiledWork.blockLimit)개") }
        }
        lines.append(session.provider == .codex
                     ? "작업을 시작·전환하거나 한 단위를 끝낼 때마다, 나중에 할 일을 들으면 waypoint-tracker 스킬을 따른다."
                     : skillHint)
        return lines.joined(separator: "\n")
    }

    /// 「3시간 전, Claude Code」「9월 20일, Codex, 오래됨」. 도구를 모르면 뺀다.
    static func statusHeader(_ status: ProjectStatus.Entry, now: Date) -> String {
        [TimeFormat.relative(status.at, now: now), status.provider?.name, status.isStale(now: now) ? "오래됨" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// 다음 세션 메모가 있는 끝나지 않은 카드 중 가장 최근에 메모를 남긴 것.
    /// 메모 시각은 `handoff` 기록(`note` 이벤트)으로 보고, 없으면(앱에서 쓴 메모 등) `updatedAt`.
    static func latestHandoff(in cards: [Card]) -> Card? {
        cards
            .filter { $0.status != .done && !($0.nextSessionNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { card -> (card: Card, at: Date) in
                let handoffs = (card.events ?? []).filter {
                    $0.type == .note && $0.payloadValues["kind"]?.stringValue == MCPTools.handoffNoteKind
                }
                return (card, handoffs.map(\.at).max() ?? card.updatedAt)
            }
            .max { $0.at < $1.at }?
            .card
    }
}
