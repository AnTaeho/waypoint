import Foundation
import SQLite3

/// Codex 내부 기억 DB(`$CODEX_HOME/memories_1.sqlite`, 표 `stage1_outputs`)를 읽기만 한다.
///
/// `file:…?mode=ro` URI와 `SQLITE_OPEN_READONLY`로 열고 `PRAGMA query_only`를 켠다. Codex가 WAL로 쓰고 있어
/// `immutable=1`은 쓰지 않는다(WAL에만 있는 행을 놓친다). WAL 읽기는 SQLite가 `-shm` 공유 메모리 색인을 함께 쓴다.
/// 표·열이 다르거나 열지 못하면 `.unreadable`.
public enum CodexMemoryStore {

    public struct Entry: Equatable, Sendable {
        public var threadID: String
        /// `raw_memory` 앞부분
        public var summary: String
        public var updatedAt: Date?

        public init(threadID: String, summary: String, updatedAt: Date?) {
            self.threadID = threadID
            self.summary = summary
            self.updatedAt = updatedAt
        }
    }

    public enum State: Equatable, Sendable {
        case missing
        case unreadable
        /// 전체 행 수와 최근 항목(최대 `limit`개)
        case entries(total: Int, recent: [Entry])

        public var count: Int? {
            if case .entries(let total, _) = self { total } else { nil }
        }
    }

    public static let fileName = "memories_1.sqlite"
    /// 항목 요약 길이(글자)
    public static let summaryLength = 240

    public static func read(path: String, limit: Int = 50) -> State {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        var url = URLComponents()
        url.scheme = "file"
        url.path = path
        url.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        guard let uri = url.string else { return .unreadable }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        defer { sqlite3_close_v2(db) }
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else { return .unreadable }
        sqlite3_busy_timeout(db, 200)
        guard sqlite3_exec(db, "PRAGMA query_only = 1", nil, nil, nil) == SQLITE_OK else { return .unreadable }

        guard let total = count(db) else { return .unreadable }
        guard let recent = recent(db, limit: limit) else { return .unreadable }
        return .entries(total: total, recent: recent)
    }

    private static func count(_ db: OpaquePointer) -> Int? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM stage1_outputs", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func recent(_ db: OpaquePointer, limit: Int) -> [Entry]? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT thread_id, raw_memory, source_updated_at FROM stage1_outputs ORDER BY source_updated_at DESC LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int(stmt, 1, Int32(max(0, limit)))
        var entries: [Entry] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return nil }
            let thread = text(stmt, 0) ?? ""
            let raw = text(stmt, 1) ?? ""
            let stamp = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2)
            entries.append(Entry(threadID: thread, summary: summarize(raw), updatedAt: stamp.map(date)))
        }
        return entries
    }

    private static func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    /// 앞 `summaryLength`자, 줄바꿈은 공백으로.
    static func summarize(_ raw: String) -> String {
        let flat = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > summaryLength ? String(flat.prefix(summaryLength)) + "…" : flat
    }

    /// 초·밀리초 모두 받는다.
    static func date(_ stamp: Int64) -> Date {
        stamp > 100_000_000_000 ? Date(timeIntervalSince1970: Double(stamp) / 1000) : Date(timeIntervalSince1970: Double(stamp))
    }
}
