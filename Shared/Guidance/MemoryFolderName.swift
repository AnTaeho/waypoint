import Foundation

/// Claude Code가 `~/.claude/projects/` 아래 폴더 이름을 정하는 규칙(대화 기록·자동 기억 공통).
///
/// 문서(sessions 「Where transcripts are stored」): 경로의 영문자·숫자가 아닌 글자를 모두 `-`로 바꾼다.
/// 바꾼 이름이 200자를 넘으면 200자로 자르고 전체 경로의 해시를 붙인다.
/// 실제 폴더로 확인: `~/workspace/projects/credit_system` → `-Users-antaeho-workspace-projects-credit-system`.
/// 글자 수는 UTF-16 단위로 센다(한글 한 글자 → `-` 하나).
public enum MemoryFolderName {

    /// 이름 길이 한도. 넘으면 해시가 붙어 이름만으로 되돌릴 수 없다.
    public static let maxLength = 200

    public static func encode(_ path: String) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(path.utf16.count)
        let dash = UInt16(UInt8(ascii: "-"))
        for unit in path.utf16 {
            let isAlnum = (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
            units.append(isAlnum ? unit : dash)
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// 폴더 이름이 이 경로의 것인가. 200자를 넘는 경로는 해시를 다시 만들 수 없어 앞 200자 + `-`로만 맞춘다.
    public static func matches(_ name: String, path: String) -> Bool {
        let encoded = encode(path)
        guard encoded.utf16.count > maxLength else { return name == encoded }
        let prefix = String(decoding: Array(encoded.utf16.prefix(maxLength)), as: UTF16.self)
        return name.hasPrefix(prefix + "-") && name.utf16.count > maxLength + 1
    }

    /// 이름에서 폴더 경로를 되돌린다(표시용). `/`부터 실제 하위 폴더를 하나씩 읽어 이름이 맞는 길을 찾는다.
    /// `-`가 `/`·`_`·`.`·공백 중 무엇이었는지 이름만으로는 알 수 없어서다. 찾지 못하면 `-`를 `/`로 바꾼 추정과 false.
    /// - Parameter budget: 읽을 폴더 수 한도(넘으면 추정으로)
    public static func locate(_ name: String, fileSystem fs: GuidanceFileSystem, budget: Int = 64) -> (path: String, onDisk: Bool) {
        let naive = "/" + name.drop(while: { $0 == "-" }).replacingOccurrences(of: "-", with: "/")
        guard name.hasPrefix("-"), name.utf16.count <= maxLength else { return (naive, false) }
        var remaining = budget
        if let found = search(dir: "/", rest: String(name.dropFirst()), fs: fs, budget: &remaining) {
            return (found, true)
        }
        return (naive, false)
    }

    private static func search(dir: String, rest: String, fs: GuidanceFileSystem, budget: inout Int) -> String? {
        guard budget > 0, let names = fs.list(dir) else { return nil }
        budget -= 1
        for child in names.sorted() {
            let encoded = encode(child)
            let isLast = rest == encoded
            guard isLast || rest.hasPrefix(encoded + "-") else { continue }
            let path = dir == "/" ? "/" + child : dir + "/" + child
            guard fs.info(path)?.isDirectory == true else { continue }
            if isLast { return path }
            if let found = search(dir: path, rest: String(rest.dropFirst(encoded.count + 1)), fs: fs, budget: &budget) {
                return found
            }
        }
        return nil
    }
}
