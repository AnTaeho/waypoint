import Foundation

/// 설치기의 「계획」. 대상 파일마다 지금 내용과 바꿀 내용을 담는다. 바뀔 것이 없으면 빈 계획이다.
/// 계획을 만드는 동안에는 아무것도 쓰지 않는다. 적용은 `IntegrationApplier`.
public struct IntegrationPlan: Equatable, Sendable {
    public enum Action: String, Sendable { case install, remove }

    /// 파일 하나의 바뀜. `after`가 nil이면 지운다.
    public struct FileChange: Equatable, Sendable {
        /// 쓸 자리(심볼릭 링크면 가리키는 파일)
        public var path: String
        /// 지금 내용. nil이면 없다
        public var before: Data?
        /// 지금 권한(없으면 nil)
        public var beforeMode: UInt16?
        public var after: Data?
        /// 쓸 권한
        public var mode: UInt16
        /// 무엇을 바꾸나(보고용, 한 줄)
        public var summary: String

        public init(path: String, before: Data?, beforeMode: UInt16?, after: Data?, mode: UInt16, summary: String) {
            self.path = path
            self.before = before
            self.beforeMode = beforeMode
            self.after = after
            self.mode = mode
            self.summary = summary
        }
    }

    /// 파일을 쓴 뒤 돌릴 명령(Claude MCP 등록). 파일 되돌리기 범위 밖이다.
    public enum Command: Equatable, Sendable {
        /// `claude mcp add --transport http --scope user waypoint <url>`
        case claudeMCPAdd(url: String)
        /// `claude mcp remove waypoint -s user`
        case claudeMCPRemove
    }

    /// 하지 않고 넘긴 단계와 까닭(사용자 것과 겹침 등)
    public struct Note: Equatable, Sendable {
        public var step: String
        public var reason: String
        public init(step: String, reason: String) { self.step = step; self.reason = reason }
    }

    public var provider: AgentProvider
    public var action: Action
    public var files: [FileChange]
    public var commands: [Command]
    public var notes: [Note]
    /// 적용할 때 백업을 남길 폴더(계획마다 하나)
    public var backupFolder: URL

    public var isEmpty: Bool { files.isEmpty && commands.isEmpty }
}

/// 설치·해제를 멈추게 하는 까닭.
public enum IntegrationInstallError: Error, Equatable, Sendable {
    /// 설정 파일을 읽지 못했거나 구조가 예상과 다르다
    case unreadable(path: String, reason: String)
    /// 사용자 설정과 겹쳐 덮어쓰지 않는다(Codex 설치기의 멈춤 조건)
    case conflict(String)
    /// 설치 자원(앱 번들의 스크립트·스킬)을 찾지 못했다
    case missingResource(String)
    /// 계획을 만든 뒤 파일이 바뀌었다. 아무것도 쓰지 않았다
    case changedSincePlan(path: String)
    /// 백업을 남기지 못했다. 아무것도 쓰지 않았다
    case backupFailed(String)
    /// 쓰다가 실패했다. `rolledBack`이면 이미 쓴 파일을 모두 이전 상태로 되돌렸다
    case writeFailed(path: String, reason: String, rolledBack: Bool, rollbackFailures: [String])
}

/// 파일 바뀜을 디스크에 적용한다. 순서: 계획 이후 바뀌지 않았는지 확인 → 대상 전부 백업 → 차례로 원자적 쓰기
/// → 하나라도 실패하면 이미 쓴 파일을 백업 내용으로 되돌린다.
public struct IntegrationApplier: Sendable {
    /// 파일 하나를 쓴다(`nil`이면 지운다). 테스트가 실패를 끼워 넣는 자리.
    public typealias Writer = @Sendable (_ path: String, _ data: Data?, _ mode: UInt16) throws -> Void

    public var writer: Writer

    public init(writer: @escaping Writer = IntegrationFile.apply) {
        self.writer = writer
    }

    /// 백업 목록 파일 이름. 폴더 안 사본과 원래 경로를 잇는다.
    public static let indexName = "paths.json"

    /// 적용하고 백업 폴더를 돌려준다(쓸 파일이 없으면 nil).
    @discardableResult
    public func apply(_ plan: IntegrationPlan) throws -> URL? {
        guard !plan.files.isEmpty else { return nil }
        for change in plan.files {
            let disk = IntegrationFile.read(change.path)
            guard disk.data == change.before else { throw IntegrationInstallError.changedSincePlan(path: change.path) }
        }
        do {
            try Self.backup(plan.files, to: plan.backupFolder)
        } catch {
            throw IntegrationInstallError.backupFailed(error.localizedDescription)
        }
        var written: [IntegrationPlan.FileChange] = []
        var createdDirectories: [String] = []
        for change in plan.files {
            do {
                if change.after != nil {
                    createdDirectories += try IntegrationFile.makeParents(of: change.path)
                }
                written.append(change)
                try writer(change.path, change.after, change.mode)
            } catch {
                let failures = Self.rollback(written, createdDirectories: createdDirectories)
                throw IntegrationInstallError.writeFailed(path: change.path, reason: error.localizedDescription,
                                                          rolledBack: failures.isEmpty, rollbackFailures: failures)
            }
        }
        return plan.backupFolder
    }

    /// 쓴 차례의 거꾸로 되돌린다. 있던 파일은 이전 내용·권한으로, 없던 파일은 지운다. 실패한 경로를 돌려준다.
    static func rollback(_ written: [IntegrationPlan.FileChange], createdDirectories: [String]) -> [String] {
        var failures: [String] = []
        for change in written.reversed() {
            do {
                try IntegrationFile.apply(path: change.path, data: change.before, mode: change.beforeMode ?? 0o600)
            } catch {
                failures.append(change.path)
            }
        }
        for dir in createdDirectories.reversed() {
            _ = rmdir(dir) // 비어 있을 때만 지워진다
        }
        return failures
    }

    /// 백업 폴더(0700)에 대상 파일 사본(0600)과 목록(`paths.json`: 사본 이름·원래 경로·있었는지·권한)을 남긴다.
    static func backup(_ files: [IntegrationPlan.FileChange], to folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.deletingLastPathComponent().path)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var index: [OrderedJSON] = []
        for (number, change) in files.enumerated() {
            let name = String(format: "%02d-", number + 1) + (change.path as NSString).lastPathComponent
            var entry: [(String, OrderedJSON)] = [("path", .string(change.path))]
            if let before = change.before {
                try IntegrationFile.writePrivate(before, to: folder.appendingPathComponent(name))
                entry.append(("file", .string(name)))
                entry.append(("mode", .string(String(change.beforeMode ?? 0o600, radix: 8))))
            } else {
                entry.append(("file", .null))
            }
            index.append(.object(entry))
        }
        let text = OrderedJSON.array(index).serialized() + "\n"
        try IntegrationFile.writePrivate(Data(text.utf8), to: folder.appendingPathComponent(indexName))
    }

    /// `<root>/<UTC 시각>-<8자>` 꼴의 새 백업 폴더 자리.
    public static func backupFolder(root: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return root.appendingPathComponent("\(formatter.string(from: date))-\(suffix)", isDirectory: true)
    }
}

/// 설치기의 파일 읽기·쓰기.
public enum IntegrationFile {
    public struct Disk: Equatable {
        public var data: Data?
        public var mode: UInt16?
    }

    /// 심볼릭 링크를 따라간 실제 경로(링크가 아니거나 없으면 그대로). 부모 폴더의 링크도 푼다.
    public static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    public static func read(_ path: String) -> Disk {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path), let data = fm.contents(atPath: path) else { return Disk(data: nil, mode: nil) }
        let mode = (try? fm.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.uint16Value
        return Disk(data: data, mode: mode)
    }

    /// 없는 부모 폴더를 만들고, 새로 만든 폴더를 바깥부터 돌려준다(되돌릴 때 지우려고).
    static func makeParents(of path: String) throws -> [String] {
        let fm = FileManager.default
        var missing: [String] = []
        var dir = (path as NSString).deletingLastPathComponent
        while !dir.isEmpty, dir != "/", !fm.fileExists(atPath: dir) {
            missing.insert(dir, at: 0)
            dir = (dir as NSString).deletingLastPathComponent
        }
        for item in missing {
            try fm.createDirectory(atPath: item, withIntermediateDirectories: false)
        }
        return missing
    }

    /// 같은 폴더의 임시 파일에 다 쓰고 권한을 맞춘 뒤 `rename`으로 바꿔 끼운다. `data`가 nil이면 지운다.
    @Sendable public static func apply(path: String, data: Data?, mode: UInt16) throws {
        let fm = FileManager.default
        guard let data else {
            if fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil {
                try fm.removeItem(atPath: path)
                _ = rmdir((path as NSString).deletingLastPathComponent) // 비게 된 폴더(스킬 폴더 등)만 지워진다
            }
            return
        }
        _ = try makeParents(of: path)
        let dir = (path as NSString).deletingLastPathComponent
        let temp = (dir as NSString).appendingPathComponent(".\((path as NSString).lastPathComponent).waypoint-\(UUID().uuidString.prefix(8))")
        guard fm.createFile(atPath: temp, contents: data, attributes: [.posixPermissions: mode]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
        }
        do {
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: temp) // umask와 상관없이
            guard rename(temp, path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            try? fm.removeItem(atPath: temp)
            throw error
        }
    }

    /// 0600 파일(백업 사본)
    static func writePrivate(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension IntegrationPlan {
    /// 대상 파일 하나를 계획에 넣는다. 지금 내용·권한과 같으면 넣지 않는다.
    /// - Parameter mode: 쓸 권한. nil이면 있던 파일의 권한을 지키고, 새 파일은 `newMode`.
    mutating func set(_ path: String, to after: Data?, mode: UInt16?, newMode: UInt16 = 0o600, summary: String) {
        let target = IntegrationFile.resolved(path)
        let disk = IntegrationFile.read(target)
        let finalMode = mode ?? disk.mode ?? newMode
        if disk.data == after && (after == nil || disk.mode == finalMode) { return }
        if after == nil && disk.data == nil { return }
        files.removeAll { $0.path == target }
        files.append(FileChange(path: target, before: disk.data, beforeMode: disk.mode, after: after,
                                mode: finalMode, summary: summary))
    }
}
