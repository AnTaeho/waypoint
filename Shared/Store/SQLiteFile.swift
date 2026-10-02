import Foundation
import SQLite3

/// 저장소 파일을 SwiftData 밖에서 직접 다룬다(TRK-46): 무결성 확인과 열린 저장소의 온라인 백업.
enum SQLiteFile {
    struct Failure: Error, CustomStringConvertible {
        var step: String
        var code: Int32
        var message: String
        var description: String { "SQLite \(step) 실패(\(code)): \(message)" }
    }

    /// `PRAGMA quick_check`가 `ok`인가. 읽기 전용으로 열어 파일을 바꾸지 않는다(체크포인트 없음).
    /// 열 수 없거나 SQLite 파일이 아니면 false.
    static func quickCheck(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var db: OpaquePointer?
        defer { sqlite3_close_v2(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0)
        else { return false }
        return String(cString: text) == "ok"
    }

    /// 열린 저장소(`source`)를 한 시점의 일관된 사본(`destination`, 새 파일)으로 뜬다(`sqlite3_backup_*`).
    /// WAL에만 있는 변경까지 담고, 사본은 롤백 저널 모드로 바꿔 파일 하나로 끝나게 한다.
    static func onlineBackup(from source: URL, to destination: URL) throws {
        var src: OpaquePointer?
        var dst: OpaquePointer?
        defer {
            sqlite3_close_v2(src)
            sqlite3_close_v2(dst)
        }
        guard sqlite3_open_v2(source.path, &src, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw failure("원본 열기", src)
        }
        sqlite3_busy_timeout(src, 2000)
        guard sqlite3_open_v2(destination.path, &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw failure("사본 열기", dst)
        }
        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            throw failure("백업 시작", dst)
        }
        var result = SQLITE_OK
        var retries = 0
        repeat {
            result = sqlite3_backup_step(backup, -1)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                retries += 1
                usleep(20_000)
            }
        } while (result == SQLITE_OK || result == SQLITE_BUSY || result == SQLITE_LOCKED) && retries < 100
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else {
            throw Failure(step: "백업", code: result, message: String(cString: sqlite3_errstr(result)))
        }
        guard sqlite3_exec(dst, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw failure("저널 모드", dst)
        }
    }

    private static func failure(_ step: String, _ db: OpaquePointer?) -> Failure {
        let code = db.map { sqlite3_errcode($0) } ?? SQLITE_CANTOPEN
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "열 수 없음"
        return Failure(step: step, code: code, message: message)
    }
}
