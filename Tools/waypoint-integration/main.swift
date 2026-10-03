import Foundation
import WaypointKit

// 앱 안 연동 설치기(`Shared/Integration/Installer/`)를 명령행으로 연다. 원격 설정 도우미(`scripts/remote-setup.sh`)가
// 원격의 설정 파일을 임시 홈에 받아 이 도구로 계획·적용한 뒤 되돌려 놓는다(TRK-53). 실제 홈에는 쓰지 않는다.
//
// 사용: waypoint-integration <plan|install|remove> --home <임시 홈> --command-home <원격 $HOME>
//         [--provider claude|codex] [--instance stable|dev] [--repo <저장소 뿌리>] [--backup-root <폴더>]
// 출력(한 줄씩): `file <홈 기준 경로> <요약>`, `command <셸 명령>`(MCP 등록 — 실행하지 않는다), `note <단계>: <이유>`.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("waypoint-integration: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let verb = arguments.first, ["plan", "install", "remove"].contains(verb) else {
    fail("사용: waypoint-integration <plan|install|remove> --home <폴더> --command-home <경로> [--provider claude|codex] [--instance stable|dev]")
}
arguments.removeFirst()
var options: [String: String] = [:]
while !arguments.isEmpty {
    let key = arguments.removeFirst()
    guard key.hasPrefix("--"), !arguments.isEmpty else { fail("값이 없는 옵션: \(key)") }
    options[String(key.dropFirst(2))] = arguments.removeFirst()
}
guard let home = options["home"], home.hasPrefix("/") else { fail("--home <절대 경로>가 필요함") }
guard let commandHome = options["command-home"], commandHome.hasPrefix("/") else { fail("--command-home <원격 홈 절대 경로>가 필요함") }
let provider: AgentProvider
switch options["provider"] ?? "claude" {
case "claude": provider = .claude
case "codex": provider = .codex
default: fail("--provider는 claude 또는 codex")
}
let instance: AppInstance
switch options["instance"] ?? "stable" {
case "stable": instance = .stable
case "dev": instance = .dev
default: fail("--instance는 stable 또는 dev")
}
let repo = URL(fileURLWithPath: options["repo"] ?? FileManager.default.currentDirectoryPath, isDirectory: true)
let backupRoot = URL(fileURLWithPath: options["backup-root"] ?? (home + "/.waypoint-integration-backups"), isDirectory: true)
let context = IntegrationInstallContext(
    home: URL(fileURLWithPath: home, isDirectory: true), commandHome: commandHome, instance: instance,
    sources: .repository(root: repo), backupRoot: backupRoot)

func relative(_ path: String) -> String {
    let root = context.home.path.hasSuffix("/") ? context.home.path : context.home.path + "/"
    return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
}

func shellCommand(_ command: IntegrationPlan.Command) -> String {
    (["claude"] + ClaudeCommandRunner.arguments(for: command)).joined(separator: " ")
}

do {
    let plan = try IntegrationInstaller.plan(provider, verb == "remove" ? .remove : .install, context: context)
    if verb != "plan", !plan.files.isEmpty {
        // 명령(MCP 등록)은 여기서 돌리지 않는다: 이 Mac의 `claude`가 원격 설정이 아닌 임시 홈을 고치게 된다.
        try IntegrationInstaller.apply(plan, context: context,
                                       runner: ClaudeCommandRunner(executable: nil, environment: [:]))
    }
    for file in plan.files { print("file \(relative(file.path)) \(file.summary)") }
    for command in plan.commands { print("command \(shellCommand(command))") }
    for note in plan.notes { print("note \(note.step): \(note.reason)") }
} catch {
    fail("\(error)")
}
