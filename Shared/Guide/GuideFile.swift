import CryptoKit
import Foundation

/// 지침 문서 파일 읽기·쓰기와 내용 해시.
public enum GuideFile {

    /// UTF-8 내용의 SHA-256(소문자 16진).
    public static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 디스크에서 읽은 파일 상태.
    public enum Disk: Equatable, Sendable {
        case missing
        case present(content: String, hash: String)

        public var content: String? {
            if case .present(let content, _) = self { content } else { nil }
        }
    }

    /// 파일이 없으면 `.missing`. UTF-8로 읽지 못하면 오류.
    public static func read(_ url: URL) throws -> Disk {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return .present(content: content, hash: hash(content))
    }

    /// 같은 폴더의 임시 파일에 다 쓴 뒤 `rename`으로 바꿔 끼운다. 읽는 쪽은 옛 내용이나 새 내용만 본다.
    /// 기존 파일의 권한은 그대로 옮긴다.
    public static func writeAtomically(_ content: String, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).waypoint-\(UUID().uuidString.prefix(8))")
        try Data(content.utf8).write(to: temp)
        do {
            if let perms = try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] {
                try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: temp.path)
            }
            guard rename(temp.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
