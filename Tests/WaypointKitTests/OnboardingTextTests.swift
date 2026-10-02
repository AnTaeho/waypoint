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
        #expect(OnboardingText.error(.unreadable(path: "/Users/me/.claude/settings.json", reason: "hooks가 객체가 아님"), home: home)
                == "설정 파일을 읽을 수 없음 · ~/.claude/settings.json")
        #expect(OnboardingText.error(.changedSincePlan(path: "/Users/me/.codex/hooks.json"), home: home)
                == "확인하는 사이 ~/.codex/hooks.json이 바뀜")
        let failed = IntegrationInstallError.writeFailed(path: "/Users/me/.claude/settings.json", reason: "권한 없음",
                                                         rolledBack: true, rollbackFailures: [])
        #expect(OnboardingText.error(failed, home: home) == "~/.claude/settings.json에 쓰지 못함 · 권한 없음 · 원래대로 되돌림")
        let stuck = IntegrationInstallError.writeFailed(path: "/a", reason: "r", rolledBack: false, rollbackFailures: ["/b", "/c"])
        #expect(OnboardingText.error(stuck, home: home).hasSuffix("되돌리지 못한 파일 2개"))
        #expect(OnboardingText.error(.conflict("기존 설정이 다릅니다"), home: home) == "직접 고친 설정과 겹침")
        let other: Error = IntegrationInstallError.missingResource("SKILL.md")
        #expect(OnboardingText.error(other, home: home) == "앱 안의 연결 파일을 찾지 못함")
    }

    /// 설치기의 실제 멈춤 문구(`CodexInstallPlanner`)를 화면 말로
    @Test func conflictsBecomePlainSentences() {
        let cases = [
            "Codex 설정에서 features.hooks=false입니다. 훅 사용 설정을 먼저 확인하세요": "Codex 설정에서 연결 꺼짐",
            "기존 waypoint MCP 설정이 다릅니다. 기존 설정을 보존합니다": "다른 Waypoint 등록이 있어 그대로 둠",
            "waypoint-tracker 스킬이 이미 있고 직접 수정됨. 기존 파일을 보존합니다": "직접 고친 /tracker 파일이 있어 그대로 둠",
            "홈 경로에 셸 확장 문자가 있어 설정할 수 없습니다": "홈 폴더 경로에 쓸 수 없는 글자가 있음",
        ]
        for (raw, text) in cases {
            #expect(OnboardingText.error(.conflict(raw), home: "/Users/me") == text)
        }
    }

    /// `IntegrationInstallation.inspect`가 내는 상세(이벤트 이름·포트)를 화면 말로
    @Test func installationDetailsBecomePlainSentences() throws {
        let cases: [(IntegrationInstallation.State, String, String)] = [
            (.ready, "설정됨", "연결됨"),
            (.missing, "설정 없음", "연결 안 됨"),
            (.missing, "Waypoint 연결 없음", "연결 안 됨"),
            (.attention, "SessionStart 연결 포트가 앱 포트 47822와 다름", "다른 Waypoint에 연결됨"),
            (.attention, "PreToolUse 일부 도구만 연결됨", "연결 일부 빠짐"),
            (.attention, "빠진 연결: Stop, SessionEnd", "연결 일부 빠짐"),
            (.attention, "Codex 설정에서 연결 꺼짐", "Codex 설정에서 연결 꺼짐"),
            (.attention, "사용자 설정에서 연결 꺼짐", "설정에서 연결 꺼짐"),
            (.attention, "설정을 읽을 수 없음", "설정 파일을 읽을 수 없음"),
            (.attention, "연결 파일을 실행할 수 없음", "연결 파일 일부 없음"),
            (.attention, "Codex 공통 연결 파일 없음", "연결 파일 일부 없음"),
            (.attention, "알 수 없는 상태", "연결 확인 필요"),
        ]
        for (state, detail, text) in cases {
            #expect(OnboardingText.installation(.init(state: state, detail: detail)) == text)
        }
        #expect(OnboardingText.installation(nil) == "연결 안 됨")
        // 실제 진단 결과: 평소용(47821)으로 연결된 홈을 Dev(47822)가 보면
        let box = InstallSandbox()
        try IntegrationInstaller.apply(try IntegrationInstaller.plan(.claude, .install, context: box.context()),
                                       context: box.context(), runner: ClaudeCommandRunner(executable: nil, environment: [:]))
        let seen = IntegrationInstallation.inspect(provider: .claude, home: box.home, port: 47822)
        #expect(seen.state == .attention && OnboardingText.installation(seen) == "다른 Waypoint에 연결됨")
        let blocker = OnboardingProgress.Blocker.attention(.claude, seen.detail)
        #expect(OnboardingText.blocker(blocker) == "Claude Code · 다른 Waypoint에 연결됨")
    }

    @Test func notesAvoidInternalNames() {
        let note = OnboardingText.note(.init(step: "MCP 등록", reason: "다른 waypoint MCP 서버가 있음"))
        #expect(note == "Waypoint 등록 건너뜀 · 다른 waypoint 등록이 있음")
        #expect(!note.contains("MCP"))
        #expect(OnboardingText.note(.init(step: "상태줄", reason: "명령 상태줄이 아님")) == "상태줄 건너뜀 · 명령 상태줄이 아님")
        #expect(OnboardingText.note(.init(step: "tracker 스킬", reason: "같은 이름의 다른 스킬이 있음")) == "/tracker 건너뜀 · 같은 이름의 다른 명령이 있음")
        #expect(OnboardingText.note(.init(step: "상태줄", reason: "직접 고친 중계 명령")) == "상태줄 건너뜀 · 직접 고친 상태줄")
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
