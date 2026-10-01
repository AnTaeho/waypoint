import Foundation

/// 재개용 도구 열기(macOS 터미널)의 순수 부분: 실행 파일 찾기와 `.command` 스크립트 글.
/// 대화 내용은 인자로 넘기지 않는다(문맥은 클립보드 복사로만). 과거 대화 잇기 옵션(`--resume` 등)도 쓰지 않는다.
public enum ToolLaunch {
    public struct Plan: Equatable, Sendable {
        public let executable: String
        public let directory: String
        public var script: String { ToolLaunch.script(executable: executable, directory: directory) }
    }

    public static func commandName(_ provider: AgentProvider) -> String {
        provider == .codex ? "codex" : "claude"
    }

    /// 앱은 launchd PATH(`/usr/bin:/bin:…`)로 뜨므로 흔한 설치 폴더를 먼저 보고, 그 뒤 앱의 PATH를 본다.
    public static func searchDirectories(provider: AgentProvider, home: String, path: String?) -> [String] {
        var directories = ["\(home)/.local/bin"]
        if provider == .claude { directories.append("\(home)/.claude/local") }
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin",
                        "\(home)/.bun/bin", "\(home)/.volta/bin"]
        directories += (path ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }
    }

    public static func executable(provider: AgentProvider, home: String, path: String?,
                                  isExecutable: (String) -> Bool) -> String? {
        let name = commandName(provider)
        return searchDirectories(provider: provider, home: home, path: path)
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first(where: isExecutable)
    }

    /// 실행 파일과 작업 폴더가 모두 있을 때만 계획을 만든다. 없으면 복사만 쓴다.
    public static func plan(provider: AgentProvider, rootPath: String, home: String, path: String?,
                            isExecutable: (String) -> Bool, isDirectory: (String) -> Bool) -> Plan? {
        let directory = expand(rootPath, home: home)
        guard !directory.isEmpty, directory.hasPrefix("/"), isDirectory(directory),
              let executable = executable(provider: provider, home: home, path: path, isExecutable: isExecutable)
        else { return nil }
        return Plan(executable: executable, directory: directory)
    }

    static func expand(_ rootPath: String, home: String) -> String {
        let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") { return home + trimmed.dropFirst() }
        return trimmed
    }

    /// 셸 작은따옴표 인용. 안의 `'`는 `'\''`로 바꾼다. 공백·한글·`$`·`` ` ``는 그대로 글자로 남는다.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Terminal.app이 사용자 로그인 셸 안에서 실행하므로 PATH(node 등)는 사용자 환경을 따른다.
    /// 스크립트는 시작하자마자 자신을 지운다.
    public static func script(executable: String, directory: String) -> String {
        """
        #!/bin/sh
        rm -f -- "$0"
        cd -- \(quote(directory)) || exit 1
        exec \(quote(executable))

        """
    }
}
