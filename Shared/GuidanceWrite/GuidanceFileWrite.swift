import Foundation

/// 프로젝트 밖 지침 파일(전역·상위 폴더·기억·`.claude/rules`·Codex 규칙) 쓰기. 지침 문서(`GuideDoc`)로 등록하지 않고
/// 파일만 다룬다: 읽은 내용과 디스크가 같은지 확인 → 규칙 파일 검사 → 지금 내용을 백업 → 원자적 쓰기(또는 지우기).
///
/// Codex 내부 기억 DB에 쓰는 길은 없다(`isWritable`이 거절하고, 이 타입은 텍스트 파일만 쓴다).
public enum GuidanceFileWrite {

    public enum Failure: Error, Equatable {
        /// 쓰기 대상이 아니다(Codex 기억 DB·관리 정책 파일 등)
        case notWritable
        /// 읽은 뒤 디스크가 바뀌었다
        case changed
        /// 규칙 파일 검사에서 걸렸다
        case invalidRules(CommandRulesCheck.Outcome)
    }

    /// 파일 하나의 바뀜. nil은 파일 없음.
    public struct Change: Equatable, Sendable {
        public var path: String
        public var before: String?
        public var after: String?

        public init(path: String, before: String?, after: String?) {
            self.path = path
            self.before = before
            self.after = after
        }

        public var inverted: Change { Change(path: path, before: after, after: before) }
    }

    /// 한 번에 쓰는 바뀜들(기억 지우기는 파일 + 색인). 되돌리기는 `inverted`를 쓴다.
    public struct ChangeSet: Equatable, Sendable {
        public var changes: [Change]
        /// 지운 항목 앞부분(알림용)
        public var preview: String
        /// 함께 지운 하위 항목 수
        public var childCount: Int
        /// 함께 지운 색인 줄 수(기억 지우기)
        public var indexLines: Int

        public init(changes: [Change], preview: String = "", childCount: Int = 0, indexLines: Int = 0) {
            self.changes = changes
            self.preview = preview
            self.childCount = childCount
            self.indexLines = indexLines
        }

        public var inverted: ChangeSet {
            ChangeSet(changes: changes.reversed().map(\.inverted), preview: preview,
                      childCount: childCount, indexLines: indexLines)
        }

        /// 「지움 · 앞부분 · 하위 2개 포함」, 기억이면 「· 색인 줄 포함」
        public var summary: String {
            var parts = ["지움"]
            if !preview.isEmpty { parts.append(preview) }
            if childCount > 0 { parts.append("하위 \(childCount)개 포함") }
            if indexLines > 0 { parts.append("색인 줄 포함") }
            return parts.joined(separator: " · ")
        }
    }

    /// 쓸 수 있는 출처 종류. 프로젝트 `CLAUDE.md` 등(`.project`·`.local`)은 지침 문서 경로(`GuideItemTarget`)로 간다.
    public static let writableKinds: Set<GuidanceKind> = [.global, .ancestor, .rule, .memory, .memoryIndex, .commandRules]

    /// 관리 정책(`/Library/…`)·Codex 기억 DB·Markdown/규칙 파일이 아닌 것은 쓰지 않는다.
    public static func isWritable(kind: GuidanceKind, path: String) -> Bool {
        guard writableKinds.contains(kind), isWritablePath(path) else { return false }
        return kind == .commandRules ? path.hasSuffix(".rules") : path.lowercased().hasSuffix(".md")
    }

    static func isWritablePath(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name.hasPrefix(CodexMemoryStore.fileName) || name.hasSuffix(".sqlite") { return false }
        if path.hasPrefix("/Library/") || path.hasPrefix("/System/") { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "rules"
    }

    /// 바뀜을 디스크에 쓴다. 모든 파일이 `before`와 같은지 먼저 확인하고(하나라도 다르면 아무것도 쓰지 않는다),
    /// 규칙 파일은 새 내용을 검사한 뒤, 파일마다 지금 내용을 백업하고 쓴다(`after`가 nil이면 지운다).
    /// - Parameter checkRules: 규칙 파일 검사. nil이면 검사하지 않는다(되돌리기·복원처럼 있던 내용으로 돌릴 때).
    public static func apply(_ changes: [Change], backups: GuidanceBackupStore, reason: GuidanceBackupStore.Reason,
                             at date: Date, checkRules: ((String) -> CommandRulesCheck.Outcome)?) throws {
        guard changes.allSatisfy({ isWritablePath($0.path) }) else { throw Failure.notWritable }
        var current: [String: Data?] = [:]
        for change in changes {
            let disk = try read(change.path)
            guard same(disk, change.before) else { throw Failure.changed }
            current[change.path] = disk
        }
        if let checkRules {
            for change in changes where change.path.hasSuffix(".rules") {
                guard let after = change.after else { continue }
                let outcome = checkRules(after)
                if !outcome.isValid { throw Failure.invalidRules(outcome) }
            }
        }
        for change in changes {
            if let data = current[change.path] ?? nil {
                try backups.save(data, of: change.path, reason: reason, at: date)
            }
            let url = URL(fileURLWithPath: change.path)
            if let after = change.after {
                try GuideFile.writeAtomically(after, to: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// 사본 내용으로 되돌린다. 지금 파일이 있으면 먼저 백업한다(까닭 `restore`). 파일이 없으면 다시 만든다.
    public static func restore(_ backup: GuidanceBackupStore.Backup, backups: GuidanceBackupStore, at date: Date) throws {
        guard isWritablePath(backup.path) else { throw Failure.notWritable }
        let data = try backups.content(of: backup)
        guard let content = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        if let disk = try read(backup.path) {
            try backups.save(disk, of: backup.path, reason: .restore, at: date)
        }
        try GuideFile.writeAtomically(content, to: URL(fileURLWithPath: backup.path))
    }

    // MARK: - 내부

    /// 없으면 nil.
    static func read(_ path: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// 디스크 바이트와 기대한 글이 바이트까지 같은가.
    static func same(_ disk: Data?, _ expected: String?) -> Bool {
        switch (disk, expected) {
        case (nil, nil): true
        case (let data?, let text?): data == Data(text.utf8)
        default: false
        }
    }
}
