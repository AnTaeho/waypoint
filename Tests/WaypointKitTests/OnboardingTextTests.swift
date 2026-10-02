import Foundation
import Testing
@testable import WaypointKit

@Suite struct OnboardingTextTests {
    @Test func planLinesUseHomePathsAndVerbs() throws {
        let box = InstallSandbox()
        let plan = try IntegrationInstaller.plan(.claude, .install, context: box.context())
        let home = box.home.path
        let lines = plan.files.map { OnboardingText.change($0, home: home) }
        #expect(lines.contains("~/.claude/settings.json · 새로 만듦"))
        #expect(lines.allSatisfy { $0.hasPrefix("~/") })
        #expect(plan.commands.map(OnboardingText.command) == ["Claude Code에 Waypoint 등록"])
        let changed = IntegrationPlan.FileChange(path: "/x", before: Data("a".utf8), beforeMode: 0o644, after: Data("b".utf8),
                                                 mode: 0o644, summary: "")
        #expect(OnboardingText.verb(changed) == "바꿈")
        var removed = changed; removed.after = nil
        #expect(OnboardingText.verb(removed) == "지움")
        var chmod = changed; chmod.after = changed.before
        #expect(OnboardingText.verb(chmod) == "권한만 바꿈")
    }

    @Test func partialResultNamesWhatFailed() throws {
        let box = InstallSandbox()
        let context = box.context()
        let plan = try IntegrationInstaller.plan(.claude, .install, context: context)
        let result = try IntegrationInstaller.apply(plan, context: context, runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        #expect(result.isPartial)
        #expect(OnboardingText.failures(result) == ["Claude Code에 Waypoint 등록 못 함 · claude 실행 파일을 찾지 못함"])
        #expect(OnboardingText.outcome(.failed("종료 코드 1"), command: .claudeMCPRemove) == "Claude Code에서 Waypoint 등록 지움 실패 · 종료 코드 1")
        #expect(OnboardingText.outcome(.done, command: .claudeMCPRemove) == nil)
    }

    @Test func errorsBecomeCauseSentences() {
        let home = "/Users/me"
        #expect(OnboardingText.error(.unreadable(path: "/Users/me/.claude/settings.json", reason: "JSON이 아님"), home: home)
                == "~/.claude/settings.json을 읽을 수 없음 · JSON이 아님")
        #expect(OnboardingText.error(.changedSincePlan(path: "/Users/me/.codex/hooks.json"), home: home)
                == "확인하는 사이 ~/.codex/hooks.json이 바뀜")
        let failed = IntegrationInstallError.writeFailed(path: "/Users/me/.claude/settings.json", reason: "권한 없음",
                                                         rolledBack: true, rollbackFailures: [])
        #expect(OnboardingText.error(failed, home: home) == "~/.claude/settings.json에 쓰지 못함 · 권한 없음 · 원래대로 되돌림")
        let stuck = IntegrationInstallError.writeFailed(path: "/a", reason: "r", rolledBack: false, rollbackFailures: ["/b", "/c"])
        #expect(OnboardingText.error(stuck, home: home).hasSuffix("되돌리지 못한 파일 2개"))
        #expect(OnboardingText.error(.conflict("기존 설정이 다릅니다"), home: home) == "직접 고친 설정과 겹침 · 기존 설정이 다릅니다")
        let other: Error = IntegrationInstallError.missingResource("SKILL.md")
        #expect(OnboardingText.error(other, home: home) == "앱 안의 연결 파일 SKILL.md을 찾지 못함")
    }

    @Test func notesAvoidInternalNames() {
        let note = OnboardingText.note(.init(step: "MCP 등록", reason: "다른 waypoint MCP 서버가 있음"))
        #expect(note == "Waypoint 등록 건너뜀 · 다른 waypoint 등록이 있음")
        #expect(!note.contains("MCP"))
        #expect(OnboardingText.note(.init(step: "상태줄", reason: "명령 상태줄이 아님")) == "상태줄 건너뜀 · 명령 상태줄이 아님")
    }

    @Test func trustLines() {
        #expect(OnboardingText.trust(.codex).contains("/hooks"))
        #expect(OnboardingText.trust(.claude).contains("새로 연 세션"))
    }
}

@Suite struct FolderDraftTests {
    @Test func folderDraftFillsNameKeyAndGuides() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("folder-draft-\(UUID().uuidString.prefix(8))")
        let root = base.appendingPathComponent("ledger-app", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "x".write(to: root.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent(".claude/CLAUDE.md"), atomically: true, encoding: .utf8)
        // 폴더는 지침 문서로 보지 않는다.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("AGENTS.md"), withIntermediateDirectories: true)

        let draft = ProjectDraft.folder(root.path + "/", taken: ["LA"])
        #expect(draft.rootPath == ProjectMatcher.normalize(root.path))
        #expect(draft.name == "ledger-app")
        #expect(draft.key == ProjectKey.suggest(name: "ledger-app", folder: "ledger-app", taken: ["LA"]))
        #expect(ProjectKey.problem(draft.key, taken: ["LA"]) == nil)
        #expect(draft.guideFiles == ["CLAUDE.md", ".claude/CLAUDE.md"])
        #expect(draft.seedCards.isEmpty && draft.summary.isEmpty && draft.stack.isEmpty)
    }
}
