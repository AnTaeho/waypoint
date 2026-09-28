import Foundation

/// 지침 문서 화면 문구.
public enum GuideFormat {

    public enum State: Equatable, Sendable {
        case synced, draft, missing, conflict
    }

    /// 충돌 > 파일 없음 > 저장 안 함 > 동기화됨.
    public static func state(conflict: Bool, missing: Bool, hasDraft: Bool) -> State {
        if conflict { return .conflict }
        if missing { return .missing }
        if hasDraft { return .draft }
        return .synced
    }

    public static func state(of doc: GuideDoc) -> State {
        state(conflict: doc.conflictContent != nil, missing: doc.isMissing, hasDraft: doc.draft != nil)
    }

    /// 「동기화됨 · 2분 전」「저장 안 함」「파일 없음」「충돌」.
    public static func statusText(_ state: State, lastSyncedAt: Date, now: Date) -> String {
        switch state {
        case .synced: "동기화됨 · \(TimeFormat.relative(lastSyncedAt, now: now))"
        case .draft: "저장 안 함"
        case .missing: "파일 없음"
        case .conflict: "충돌"
        }
    }

    public static func sourceName(_ source: GuideSource) -> String {
        switch source {
        case .app: "앱"
        case .local: "로컬"
        }
    }

    /// 「섹션 5개 · 42줄」. 제목이 없으면 「42줄」.
    public static func size(of content: String) -> String {
        let lines = LineDiff.lines(content).count
        let sections = MarkdownParser.headings(in: MarkdownParser.parse(content)).count
        return sections > 0 ? "섹션 \(sections)개 · \(lines)줄" : "\(lines)줄"
    }

    /// 홈 폴더를 「~」로 줄인 경로.
    public static func displayPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
