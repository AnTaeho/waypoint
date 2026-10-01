import Foundation

/// Codex의 JSON 값·apply_patch 입력을 공유 훅 처리기가 쓰는 형식으로 맞춘다.
/// 전사 파일을 읽지 않고 훅 입력만 사용한다.
public enum CodexHookAdapter {
    public static func toolInput(_ value: Any?) -> [String: Any] {
        if let object = value as? [String: Any] { return object }
        guard let text = value as? String else { return [:] }
        if let object = jsonObject(text) { return object }
        return ["command": text]
    }

    public static func toolResponse(_ value: Any?) -> [String: Any] {
        let object: [String: Any]
        if let dictionary = value as? [String: Any] {
            object = dictionary
        } else if let text = value as? String {
            object = jsonObject(text) ?? ["stdout": text]
        } else {
            return [:]
        }
        var normalized = object
        if normalized["stdout"] == nil {
            normalized["stdout"] = object["output"] as? String ?? object["text"] as? String
        }
        return normalized
    }

    /// 성공 결과에 실제로 나온 파일만 기록한다. 실패한 패치와 추정한 파일 변경은 기록하지 않는다.
    public static func changedFiles(_ input: HookInput) -> [(path: String, added: Int, removed: Int)] {
        guard let patch = input.toolInput["command"] as? String,
              let output = input.toolResponse["stdout"] as? String,
              output.contains("Success. Updated the following files:")
        else { return [] }
        if let metadata = input.toolResponse["metadata"] as? [String: Any],
           let code = metadata["exit_code"] as? Int, code != 0 { return [] }
        if let code = input.toolResponse["exit_code"] as? Int, code != 0 { return [] }

        struct Delta { var added = 0; var removed = 0 }
        var deltas: [String: Delta] = [:]
        var current: String?
        for line in patch.components(separatedBy: .newlines) {
            if let path = path(after: ["*** Add File: ", "*** Update File: ", "*** Delete File: "], in: line) {
                current = path
                deltas[path] = deltas[path] ?? Delta()
            } else if let destination = path(after: ["*** Move to: "], in: line), let old = current {
                deltas[destination] = deltas.removeValue(forKey: old) ?? Delta()
                current = destination
            } else if line.hasPrefix("*** ") {
                if line == "*** End Patch" { current = nil }
            } else if let current {
                if line.hasPrefix("+") { deltas[current, default: Delta()].added += 1 }
                if line.hasPrefix("-") { deltas[current, default: Delta()].removed += 1 }
            }
        }

        var seen = Set<String>()
        return output.components(separatedBy: .newlines).compactMap { line in
            guard let path = path(after: ["A ", "M ", "D "], in: line),
                  let delta = deltas[path], seen.insert(path).inserted
            else { return nil }
            let absolute = path.hasPrefix("/") ? path : URL(fileURLWithPath: input.cwd, isDirectory: true)
                .appendingPathComponent(path).standardizedFileURL.path
            return (absolute, delta.added, delta.removed)
        }
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func path(after prefixes: [String], in line: String) -> String? {
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        let path = String(line.dropFirst(prefix.count))
        return path.isEmpty ? nil : path
    }
}
