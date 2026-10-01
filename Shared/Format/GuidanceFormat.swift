import Foundation

/// 지침 출처 화면 문구.
public enum GuidanceFormat {

    public static func toolName(_ tool: GuidanceTool) -> String {
        switch tool {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public static func kindName(_ kind: GuidanceKind) -> String {
        switch kind {
        case .global: "전역"
        case .ancestor: "상위 폴더"
        case .project: "프로젝트"
        case .local: "개인"
        case .rule: "규칙"
        case .memory: "기억"
        case .memoryIndex: "기억 목록"
        case .commandRules: "명령 규칙"
        case .codexMemory: "Codex 기억"
        }
    }

    /// 「12줄」「항목 3」「규칙 33」, 읽지 못하면 「읽을 수 없음」.
    public static func count(_ source: GuidanceSource) -> String {
        guard let n = source.entryCount else { return "읽을 수 없음" }
        switch source.kind {
        case .memoryIndex, .codexMemory: return "항목 \(n)"
        case .commandRules: return "규칙 \(n)"
        default: return "\(n)줄"
        }
    }

    /// 목록 줄 이름. `base` 아래면 상대 경로, 기억은 파일 이름, Codex 기억 DB는 「Codex 기억」.
    public static func title(_ source: GuidanceSource, base: String? = nil, home: String = NSHomeDirectory()) -> String {
        if source.kind == .codexMemory { return "Codex 기억" }
        if source.isMemory { return (source.path as NSString).lastPathComponent }
        if let base, source.path.hasPrefix(base + "/") { return String(source.path.dropFirst(base.count + 1)) }
        return GuideFormat.displayPath(source.path, home: home)
    }

    /// 「Claude · 기억 목록 · 항목 3 · 1.2KB」
    public static func facts(_ source: GuidanceSource) -> String {
        var parts = [toolName(source.tool), kindName(source.kind), count(source)]
        if source.kind != .codexMemory || source.entryCount != nil { parts.append(size(source.size)) }
        return parts.joined(separator: " · ")
    }

    public static func size(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: kb < 10 ? "%.1fKB" : "%.0fKB", kb) }
        return String(format: "%.1fMB", kb / 1024)
    }

    /// 짝짓지 못한 기억 폴더 이름표: 되돌린 경로, 실제로 없으면 「· 없는 폴더」.
    public static func otherFolderTitle(path: String, onDisk: Bool, home: String = NSHomeDirectory()) -> String {
        let display = GuideFormat.displayPath(path, home: home)
        return onDisk ? display : "\(display) · 없는 폴더"
    }
}
