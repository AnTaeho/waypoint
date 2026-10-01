import AppKit
import WaypointKit

/// 재개용 도구 열기. 임시 `.command` 파일을 Terminal.app으로 연다.
/// 다른 앱 조종(Apple Events)을 쓰지 않아 자동화 권한을 묻지 않는다.
@MainActor
enum ToolLauncher {
    static let terminalID = "com.apple.Terminal"

    static var terminalURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalID)
    }

    /// Terminal.app과 도구 실행 파일, 작업 폴더가 모두 있을 때만. 없으면 nil(복사만 쓴다).
    static func plan(provider: AgentProvider, rootPath: String) -> ToolLaunch.Plan? {
        guard terminalURL != nil else { return nil }
        let files = FileManager.default
        func isDirectory(_ path: String) -> Bool {
            var directory: ObjCBool = false
            return files.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
        return ToolLaunch.plan(provider: provider, rootPath: rootPath,
                               home: files.homeDirectoryForCurrentUser.path,
                               path: ProcessInfo.processInfo.environment["PATH"],
                               isExecutable: { files.isExecutableFile(atPath: $0) && !isDirectory($0) },
                               isDirectory: isDirectory)
    }

    /// 스크립트를 쓰고 Terminal.app으로 연다. 결과는 메인 액터에서 알린다.
    static func open(_ plan: ToolLaunch.Plan, provider: AgentProvider, completion: @escaping @MainActor (Bool) -> Void) {
        guard let terminal = terminalURL, let script = try? write(plan, provider: provider) else {
            completion(false)
            return
        }
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { try? FileManager.default.removeItem(at: script) }
            Task { @MainActor in completion(error == nil) }
        }
    }

    private static func write(_ plan: ToolLaunch.Plan, provider: AgentProvider) throws -> URL {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("waypoint-launch", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("\(ToolLaunch.commandName(provider))-\(UUID().uuidString).command")
        try Data(plan.script.utf8).write(to: url, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
