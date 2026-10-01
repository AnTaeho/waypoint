import Foundation
import SwiftData

/// `project_init`: 검사를 통과하면 앱 메모리에 초안을 두고 바로 `pending`으로 답한다(사용자 확인을 기다리지 않는다).
extension MCPTools {

    /// 초기 카드 최대 수
    public static let seedCardLimit = 8
    public static let initPendingMessage = "Waypoint 앱에서 확인하고 등록해 주세요."

    func projectInit(_ args: JSONValue) throws -> JSONValue {
        guard let drafts else { throw MCPToolError("확인 창을 열 수 없음(앱에서만 동작)") }
        let root = ProjectMatcher.normalize(try requiredString(args, "cwd").trimmingCharacters(in: .whitespaces), home: home)
        guard root.hasPrefix("/") else { throw MCPToolError("cwd는 절대 경로여야 함: \(root)") }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("폴더 없음: \(root)")
        }
        if let existing = ProjectMatcher.project(for: root, in: allProjects(), home: home) {
            throw MCPToolError("이미 등록된 폴더: \(existing.key) (\(existing.name), \(existing.rootPath))")
        }
        if let archived = ProjectRegistry.project(atRoot: root, in: context, home: home) {
            throw MCPToolError("보관된 프로젝트 \(archived.key)(\(archived.name))가 이 폴더를 씀. 앱에서 보관 해제하면 다시 기록함")
        }

        let name = try requiredString(args, "name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPToolError("name이 비어 있음") }
        let seeds = try seedCards(args)
        let (guides, missing) = try guideFiles(args, root: root)

        let taken = ProjectRegistry.takenKeys(in: context)
        let folder = (root as NSString).lastPathComponent
        var warnings: [String] = []
        let key: String
        if let raw = optionalString(args, "key"), !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            key = ProjectKey.normalize(raw)
            let suggestion = ProjectKey.suggest(name: name, folder: folder, taken: taken)
            switch ProjectKey.problem(key, taken: taken) {
            case .format: warnings.append("key \(key)는 영문 대문자 2–5자가 아님. 앱에서 고쳐야 등록됨(예: \(suggestion))")
            case .taken: warnings.append("key \(key)는 이미 쓰는 키. 앱에서 고쳐야 등록됨(예: \(suggestion))")
            case nil: break
            }
        } else {
            key = ProjectKey.suggest(name: name, folder: folder, taken: taken)
        }

        let draft = ProjectDraft(
            rootPath: root, name: name, key: key,
            summary: optionalString(args, "summary")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stack: ProjectRegistry.cleanStack(try stringArray(args, "stack")),
            guideFiles: guides, seedCards: seeds, createdAt: now(), provider: try provider(args)
        )
        let replaced = drafts.submit(draft)

        var result: [String: JSONValue] = [
            "status": "pending",
            "message": .string(Self.initPendingMessage),
            "draft": [
                "rootPath": .string(root),
                "name": .string(name),
                "key": .string(key),
                "guideFiles": .array(guides.map { .string($0) }),
                "seedCards": JSONValue(seeds.count),
            ],
            "replacedDraft": .bool(replaced),
        ]
        if !missing.isEmpty { result["missingGuideFiles"] = .array(missing.map { .string($0) }) }
        if !warnings.isEmpty { result["warnings"] = .array(warnings.map { .string($0) }) }
        return .object(result)
    }

    /// 폴더 아래 실제 `.md`·`.txt` 파일만 상대 경로로(순서 유지, 중복 제거). 나머지는 없는 파일로.
    func guideFiles(_ args: JSONValue, root: String) throws -> (found: [String], missing: [String]) {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        var found: [String] = [], missing: [String] = []
        for raw in try stringArray(args, "guideFiles") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let expanded = ProjectMatcher.normalize(trimmed, home: home)
            let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : rootURL.appendingPathComponent(trimmed)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
                  let rel = GuidePaths.relativePath(of: url, under: rootURL)
            else {
                missing.append(trimmed)
                continue
            }
            if !found.contains(rel) { found.append(rel) }
        }
        return (found, missing)
    }

    /// `seedCards: [{title, status: next|idea, kind?, body?}]`, 최대 8개.
    func seedCards(_ args: JSONValue) throws -> [ProjectDraft.SeedCard] {
        guard let raw = args["seedCards"], !raw.isNull else { return [] }
        guard let items = raw.arrayValue else { throw MCPToolError("seedCards는 배열") }
        guard items.count <= Self.seedCardLimit else {
            throw MCPToolError("seedCards는 최대 \(Self.seedCardLimit)개(받은 것 \(items.count)개)")
        }
        return try items.map { item in
            guard let title = item["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                throw MCPToolError("seedCards 항목에 title이 필요함")
            }
            let status: CardStatus
            switch item["status"]?.stringValue {
            case nil, "next": status = .next
            case "idea": status = .idea
            default: throw MCPToolError("seedCards의 status는 next·idea 중 하나")
            }
            let kind: CardKind
            if let rawKind = item["kind"]?.stringValue {
                guard let k = CardKind(rawValue: rawKind) else { throw MCPToolError("seedCards의 kind는 task·idea·bug 중 하나") }
                kind = k
            } else {
                kind = status == .idea ? .idea : .task
            }
            return ProjectDraft.SeedCard(title: title, status: status, kind: kind, body: item["body"]?.stringValue ?? "")
        }
    }

    /// 문자열 배열. 없으면 빈 배열.
    func stringArray(_ args: JSONValue, _ key: String) throws -> [String] {
        guard let raw = args[key], !raw.isNull else { return [] }
        guard let items = raw.arrayValue else { throw MCPToolError("\(key)는 문자열 배열") }
        return try items.map { item in
            guard let s = item.stringValue else { throw MCPToolError("\(key)는 문자열 배열") }
            return s
        }
    }
}
