import Foundation
import Testing
@testable import WaypointKit

/// 도구 열기의 순수 부분만 시험한다. 실제 터미널은 열지 않는다.
@Suite struct ToolLaunchTests {
    private let home = "/Users/me"

    @Test func findsExecutableInCommonFoldersBeforeLaunchdPath() {
        let installed: Set<String> = ["/Users/me/.local/bin/claude", "/usr/bin/claude", "/opt/homebrew/bin/codex"]
        let path = "/usr/bin:/bin:/usr/sbin:/sbin"
        #expect(ToolLaunch.executable(provider: .claude, home: home, path: path, isExecutable: installed.contains)
                == "/Users/me/.local/bin/claude")
        #expect(ToolLaunch.executable(provider: .codex, home: home, path: path, isExecutable: installed.contains)
                == "/opt/homebrew/bin/codex")
        #expect(ToolLaunch.executable(provider: .claude, home: home, path: "/custom/bin:relative",
                                      isExecutable: { $0 == "/custom/bin/claude" }) == "/custom/bin/claude")
        #expect(!ToolLaunch.searchDirectories(provider: .claude, home: home, path: "relative").contains("relative"))
    }

    @Test func missingExecutableOrFolderMeansNoLaunch() {
        let dirs: Set<String> = ["/work/app"]
        #expect(ToolLaunch.plan(provider: .codex, rootPath: "/work/app", home: home, path: nil,
                                isExecutable: { _ in false }, isDirectory: dirs.contains) == nil)
        #expect(ToolLaunch.plan(provider: .claude, rootPath: "/work/gone", home: home, path: nil,
                                isExecutable: { _ in true }, isDirectory: dirs.contains) == nil)
        #expect(ToolLaunch.plan(provider: .claude, rootPath: "  ", home: home, path: nil,
                                isExecutable: { _ in true }, isDirectory: { _ in true }) == nil)
        // Claude만 있으면 Codex 단축은 없다.
        let onlyClaude: (String) -> Bool = { $0.hasSuffix("/claude") }
        #expect(ToolLaunch.plan(provider: .claude, rootPath: "/work/app", home: home, path: nil,
                                isExecutable: onlyClaude, isDirectory: dirs.contains) != nil)
        #expect(ToolLaunch.plan(provider: .codex, rootPath: "/work/app", home: home, path: nil,
                                isExecutable: onlyClaude, isDirectory: dirs.contains) == nil)
    }

    @Test func expandsTildeAndQuotesSpacesKoreanAndQuotes() throws {
        let folder = "/Users/me/작업 폴더/it's $HOME `x`"
        let plan = try #require(ToolLaunch.plan(
            provider: .claude, rootPath: "~/작업 폴더/it's $HOME `x`", home: home, path: nil,
            isExecutable: { $0 == "/Users/me/.local/bin/claude" }, isDirectory: { $0 == folder }))
        #expect(plan.directory == folder)
        #expect(ToolLaunch.quote("it's") == #"'it'\''s'"#)
        let lines = plan.script.split(separator: "\n").map(String.init)
        #expect(lines == [
            "#!/bin/sh",
            #"rm -f -- "$0""#,
            #"cd -- '/Users/me/작업 폴더/it'\''s $HOME `x`' || exit 1"#,
            "exec '/Users/me/.local/bin/claude'",
        ])
    }

    @Test func scriptRunsInShellAndCarriesNoConversationOrResumeFlag() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint 테스트 it's \(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        // 도구 대신 /bin/pwd를 실행하게 해 셸이 따옴표를 그대로 풀어 폴더로 옮겨 가는지 본다(터미널은 열지 않는다).
        let plan = ToolLaunch.Plan(executable: "/bin/pwd", directory: folder)
        let script = (folder as NSString).appendingPathComponent("run.command")
        try plan.script.write(toFile: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(URL(fileURLWithPath: printed.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: folder).resolvingSymlinksInPath().path)
        #expect(!FileManager.default.fileExists(atPath: script))
        let real = ToolLaunch.script(executable: "/Users/me/.local/bin/claude", directory: "/work/app")
        #expect(!real.contains("--resume") && !real.contains("--continue") && !real.contains(" -r"))
    }
}
