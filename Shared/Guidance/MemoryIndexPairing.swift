import Foundation

/// `MEMORY.md` 색인 줄과 같은 폴더의 기억 파일을 파일 이름으로 짝짓는다.
public struct MemoryIndexPairing: Equatable, Sendable {
    public struct Pair: Equatable, Sendable {
        /// 색인 줄 항목 id
        public var entry: [Int]
        public var file: String
    }

    public var pairs: [Pair]
    /// 가리키는 파일이 폴더에 없는 색인 줄(항목 id)
    public var orphanEntries: [[Int]]
    /// 색인 줄이 없는 기억 파일 이름(이름순)
    public var unindexedFiles: [String]

    /// - Parameters:
    ///   - index: `MEMORY.md`를 `.memoryIndex`로 나눈 문서
    ///   - files: 같은 폴더의 기억 파일 이름(`MEMORY.md` 제외해도, 넣어도 된다)
    public init(index: GuidanceDocument, files: [String]) {
        let names = Set(files.filter { $0 != "MEMORY.md" })
        var pairs: [Pair] = []
        var orphans: [[Int]] = []
        var used: Set<String> = []
        for item in index.items where item.kind == .indexEntry {
            let name = Self.fileName(item.link ?? "")
            if names.contains(name) {
                pairs.append(Pair(entry: item.id, file: name))
                used.insert(name)
            } else {
                orphans.append(item.id)
            }
        }
        self.pairs = pairs
        self.orphanEntries = orphans
        self.unindexedFiles = names.subtracting(used).sorted()
    }

    /// 링크 대상의 파일 이름(`./a.md`, `a.md#절`, `%20` 풀기)
    static func fileName(_ link: String) -> String {
        var target = link
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        target = target.removingPercentEncoding ?? target
        return (target as NSString).lastPathComponent
    }
}
