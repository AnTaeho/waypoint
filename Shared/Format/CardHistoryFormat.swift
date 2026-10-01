import Foundation

/// 카드 히스토리 한 줄의 앞 표시.
public enum HistoryMarker: String, Sendable, Hashable {
    case active, next, done, idea, neutral, file, commit, note
}

/// 카드 히스토리 한 줄. `code`는 모노로 보일 부분(파일 이름·커밋 해시), 없으면 nil.
public struct HistoryLine: Sendable, Hashable {
    public let marker: HistoryMarker
    public let text: String
    public let code: String?
    /// 세션 표시(「sess·7f2a」「↳ test-writer」). 없으면 nil.
    public let session: String?
    public let at: Date
}

/// 변경된 파일 한 줄(경로별 합계).
public struct ChangedFile: Sendable, Hashable {
    public let path: String
    public let added: Int
    public let removed: Int
    public let lastAt: Date
}

public enum CardHistoryFormat {

    /// 이 카드의 이벤트를 최신순 줄로. 보일 문구가 없는 이벤트는 뺀다.
    public static func lines(for card: Card) -> [HistoryLine] {
        (card.events ?? [])
            .sorted { $0.at > $1.at }
            .compactMap(line(for:))
    }

    public static func line(for event: Event) -> HistoryLine? {
        let p = event.payloadValues
        let session = event.session.map(SessionFormat.label(for:))
        func make(_ marker: HistoryMarker, _ text: String, code: String? = nil) -> HistoryLine {
            HistoryLine(marker: marker, text: text, code: code, session: session, at: event.at)
        }
        switch event.type {
        case .cardCreated:
            let status = p["status"]?.stringValue.flatMap(CardStatus.init(rawValue:))
            let text = status.map { "카드 생성 · \(CardFormat.statusName($0))" } ?? "카드 생성"
            return make(status == .idea ? .idea : .next, text)
        case .cardStatus:
            guard let to = p["to"]?.stringValue.flatMap(CardStatus.init(rawValue:)) else { return nil }
            let from = p["from"]?.stringValue.flatMap(CardStatus.init(rawValue:))
            let text = from.map { "\(CardFormat.statusName($0)) → \(CardFormat.statusName(to))" }
                ?? CardFormat.statusName(to)
            return make(marker(for: to), text)
        case .cardAttached:
            return make(.active, "세션 연결")
        case .cardDetached:
            if [SessionSweep.reasonInactive, "inactive-24h"].contains(p["reason"]?.stringValue ?? "") {
                return make(.neutral, "추적 만료 · 활동 확인 시간 초과")
            }
            if p["reason"]?.stringValue == SessionSweep.reasonProcessGone {
                return make(.neutral, "세션 종료 · 프로세스 종료 확인")
            }
            return make(.neutral, "세션 연결 끝")
        case .fileChanged:
            guard let path = p["path"]?.stringValue, !path.isEmpty else { return nil }
            let name = (path as NSString).lastPathComponent
            let delta = CardFormat.lineDelta(added: p["added"]?.intValue ?? 0, removed: p["removed"]?.intValue ?? 0)
            return make(.file, "파일 변경 \(delta)", code: name)
        case .commit:
            guard let hash = p["hash"]?.stringValue, !hash.isEmpty else { return nil }
            let message = p["message"]?.stringValue ?? ""
            return make(.commit, message.isEmpty ? "커밋" : "커밋 · \(message)", code: String(hash.prefix(7)))
        case .note:
            if p["kind"]?.stringValue == CardEditing.criterionNoteKind {
                guard let text = p["text"]?.stringValue else { return nil }
                let done = p["isDone"]?.boolValue ?? false
                return make(.note, "완료 조건 \(done ? "체크" : "해제") · \(text)")
            }
            if p["kind"]?.stringValue == PromptRetention.promptKind, (p["text"]?.stringValue ?? "").isEmpty {
                return make(.note, ActivityEntryFormat.clearedPromptText)
            }
            guard let text = p["text"]?.stringValue, !text.isEmpty else { return nil }
            return make(.note, text)
        case .check:
            guard let record = CheckRecord(event: event) else { return nil }
            return make(.neutral, EvidenceFormat.historyText(record), code: EvidenceFormat.shortCommand(record.command))
        case .sessionStart, .sessionEnd, .guideSynced:
            return nil
        }
    }

    static func marker(for status: CardStatus) -> HistoryMarker {
        switch status {
        case .active: .active
        case .next: .next
        case .done: .done
        case .idea: .idea
        case .archived: .neutral
        }
    }

    /// `file.changed` 이벤트를 경로별로 합친다. 최근에 바뀐 파일부터.
    public static func changedFiles(for card: Card) -> [ChangedFile] {
        var byPath: [String: ChangedFile] = [:]
        for event in card.events ?? [] where event.type == .fileChanged {
            let p = event.payloadValues
            guard let path = p["path"]?.stringValue, !path.isEmpty else { continue }
            let added = p["added"]?.intValue ?? 0, removed = p["removed"]?.intValue ?? 0
            let old = byPath[path]
            byPath[path] = ChangedFile(
                path: path,
                added: (old?.added ?? 0) + added,
                removed: (old?.removed ?? 0) + removed,
                lastAt: max(old?.lastAt ?? .distantPast, event.at)
            )
        }
        return byPath.values.sorted { ($0.lastAt, $1.path) > ($1.lastAt, $0.path) }
    }
}
