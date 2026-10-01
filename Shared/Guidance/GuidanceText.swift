import Foundation

/// 출처 내용 보기용 나누기.
public enum GuidanceText {

    /// 맨 앞 `---` 줄로 둘러싼 머리(기억 파일의 name·description·type 등)와 나머지 본문.
    /// 닫는 줄이 없으면 머리 없음으로 본다.
    public static func splitHeader(_ content: String) -> (header: String?, body: String) {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (nil, content) }
        let header = lines[1..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .newlines)
        return (header.isEmpty ? nil : header, body)
    }

    /// 보기 화면이 읽는 앞부분 한도
    public static let readLimit = 2 << 20

    /// 파일을 앞에서 `readLimit`까지 읽어 문자열로(UTF-8, 깨진 바이트는 대체 문자). 없으면 nil.
    public static func load(_ path: String, fileSystem: GuidanceFileSystem = DiskGuidanceFileSystem()) -> String? {
        fileSystem.read(path, maxBytes: readLimit).map { String(decoding: $0, as: UTF8.self) }
    }
}
