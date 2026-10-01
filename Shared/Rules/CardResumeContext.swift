import Foundation

/// 기존 기록으로 재개 문맥을 만든다. 생성·복사는 카드나 세션 상태를 바꾸지 않는다.
public enum CardResumeContext {
    public static func unavailableReason(_ card: Card) -> String? {
        guard let project = card.project else { return "프로젝트 없음" }
        if project.archivedAt != nil { return "보관한 프로젝트" }
        if card.status == .archived { return "보관한 카드" }
        if card.status == .done { return "완료한 카드" }
        if project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "작업 폴더 없음"
        }
        return nil
    }

    public static func recentFiles(_ card: Card) -> [String] {
        var seen = Set<String>()
        return records(card).filter { $0.type == .fileChanged }.compactMap { event in
            guard let path = event.payloadValues["path"]?.stringValue, !path.isEmpty,
                  seen.insert(path).inserted else { return nil }
            return path
        }
    }

    public static func text(card: Card, provider: AgentProvider) -> String? {
        guard unavailableReason(card) == nil, let project = card.project else { return nil }
        let skill = provider == .codex ? "waypoint-tracker" : "tracker"
        var lines = [
            "Waypoint 카드 \(card.displayID)의 작업을 \(provider.name)에서 이어가 주세요.",
            "",
            "먼저 \(skill) 스킬을 따라 다음 순서로 연결해 주세요.",
            "1. 아래 작업 폴더를 project_resolve(cwd)로 확인하고 프로젝트 키가 \(project.key)인지 확인하세요.",
            "2. 현재 대화에 주입된 실제 sessionId를 사용하세요. 과거 세션 ID를 재사용하거나 새 ID를 만들지 마세요.",
            provider == .codex
                ? "   주입 ID가 없으면 CODEX_SESSION_ID 또는 CODEX_THREAD_ID를 확인하세요. 둘 다 있으면 같은지 확인하고 codex: 접두사를 한 번만 붙이세요."
                : "   주입된 sessionId가 없으면 Waypoint 연동 상태를 확인하도록 안내하세요.",
            "3. session_bind(project: \(project.key), sessionId: 현재 실제 ID, provider: \(provider.rawValue), cwd: 현재 세션 시작 폴더의 절대 경로)로 연결하세요.",
            "4. card_get(id: \(card.displayID))으로 최신 내용과 상태를 읽으세요. 완료·보관 상태로 바뀌었다면 자동으로 재개하지 마세요.",
            "5. card_start(id: \(card.displayID), sessionId: 연결 결과의 ID)를 호출하세요. otherSessions가 있으면 사용자에게 알리고 작업 범위를 확인하세요.",
            "6. 연결에 실패하면 추적이 시작됐다고 말하지 말고 이유를 알려 주세요. 연결되면 실제 파일과 지침을 확인하고 남은 작업을 진행하세요.",
            "완료 조건을 확인하고 card_handoff로 다음 메모를 남기세요. 완료 처리는 사용자의 지시에 따르세요.",
            "",
            "아래는 복사 시점의 참고 기록입니다. 최신 card_get 결과와 실제 파일을 우선하세요.",
            "프로젝트: \(project.name) (\(project.key))",
            "작업 폴더: \((project.rootPath as NSString).expandingTildeInPath)",
            "카드: \(card.displayID) · \(card.title)",
            "상태: \(CardFormat.statusName(card.status))",
            "",
            "## 목표와 작업 내용",
            excerpt(card.body, limit: 6000, empty: "등록된 본문 없음. 카드 제목과 최신 요청에서 목표를 확인하세요."),
            "",
            "## 마지막 인수인계 메모",
            excerpt(card.nextSessionNote ?? "", limit: 3000, empty: "등록된 메모 없음. 실제 변경 내용부터 확인하세요."),
            "",
            "## 남은 완료 조건"
        ]
        let remaining = card.criteria.filter { !$0.isDone }
        lines += remaining.isEmpty ? [card.criteria.isEmpty ? "등록된 완료 조건 없음." : "모든 등록 조건이 체크됨. 최종 검증 여부를 확인하세요."]
            : remaining.prefix(20).map { "- " + excerpt($0.text, limit: 500) }
        if remaining.count > 20 { lines.append("외 \(remaining.count - 20)개 — card_get에서 전체 확인") }
        lines += ["", "## 최근 변경 파일 (이 카드에 기록된 경로)"]
        let files = recentFiles(card)
        lines += files.isEmpty ? ["기록된 파일 없음."] : files.prefix(10).map { "- \($0)" }
        if files.count > 10 { lines.append("외 \(files.count - 10)개 — 카드 활동에서 확인") }
        lines += ["", "## 최근 커밋"]
        let commits = records(card).filter { $0.type == .commit }.prefix(3)
        lines += commits.isEmpty ? ["기록된 커밋 없음."] : commits.map {
            "- \(String(($0.payloadValues["hash"]?.stringValue ?? "").prefix(12))) \(excerpt($0.payloadValues["message"]?.stringValue ?? "", limit: 300))"
        }
        return lines.joined(separator: "\n")
    }

    private static func records(_ card: Card) -> [Event] {
        (card.events ?? []).filter { $0.project?.id == card.project?.id && $0.card?.id == card.id }
            .sorted { $0.at == $1.at ? $0.id.uuidString < $1.id.uuidString : $0.at > $1.at }
    }

    private static func excerpt(_ text: String, limit: Int, empty: String = "") -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return empty }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "\n[일부 생략 — card_get에서 전체 확인]" : trimmed
    }
}
