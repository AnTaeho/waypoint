import Foundation

public enum ActivityEntryFormat {
    /// 보관 기간이 지나 문장을 지운 요청 이벤트의 표시(`PromptRetention`).
    public static let clearedPromptText = "요청"
    /// 문장이 남은 요청 이벤트의 보조 글. 문장을 지운 요청은 보조 글이 비어 세션 묶음 제목으로 쓰지 않는다.
    public static let promptDetail = "사용자 요청"

    public static func entry(_ event: Event) -> ActivityEntry? {
        let p = event.payloadValues
        var text: String
        var detail = ""
        var kind = event.type.rawValue
        switch event.type {
        case .fileChanged:
            guard let path = p["path"]?.stringValue else { return nil }
            text = path
            detail = "+\(p["added"]?.intValue ?? 0) −\(p["removed"]?.intValue ?? 0)"
        case .commit:
            text = p["message"]?.stringValue ?? "커밋"
            detail = String((p["hash"]?.stringValue ?? "").prefix(10))
        case .sessionStart: text = "세션 시작"
        case .sessionEnd:
            let reason = p["reason"]?.stringValue ?? ""
            text = [SessionSweep.reasonInactive, "inactive-24h"].contains(reason) ? "추적 만료" : "세션 종료"
            if reason == SessionSweep.reasonProcessGone { detail = "프로세스 종료 확인" }
        case .note:
            kind = p["kind"]?.stringValue ?? "note"
            if kind == "project.bound" {
                text = "작업 프로젝트 연결"; detail = p["to"]?.stringValue ?? ""
            } else if kind == PromptRetention.promptKind, (p["text"]?.stringValue ?? "").isEmpty {
                text = clearedPromptText
            } else {
                guard let content = p["text"]?.stringValue, !content.isEmpty else { return nil }
                text = content
                detail = kind == "handoff" ? "다음 세션 메모" : kind == PromptRetention.promptKind ? promptDetail : "메모"
            }
        case .guideSynced:
            text = "지침 문서 변경"; detail = p["relPath"]?.stringValue ?? ""
        case .cardStatus:
            guard let status = p["to"]?.stringValue.flatMap(CardStatus.init(rawValue:)) else { return nil }
            text = CardFormat.statusName(status)
            if status == .done { kind = "done" }
        case .cardCreated: text = "카드 생성"
        case .cardAttached: text = "세션 연결"
        case .cardDetached: text = CardHistoryFormat.line(for: event)?.text ?? "세션 연결 끝"
        }
        return ActivityEntry(id: event.id, at: event.at, card: event.card, type: event.type, kind: kind,
                             text: text, detail: detail, added: p["added"]?.intValue ?? 0, removed: p["removed"]?.intValue ?? 0)
    }
}
