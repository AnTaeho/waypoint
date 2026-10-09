import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 검증 명령 판정(SPEC 5장 「검증 근거」).
@Suite struct VerificationCommandTests {
    func outcome(_ command: String, _ code: Int?) -> CheckOutcome? {
        VerificationCommand.parse(command).map { VerificationCommand.outcome($0, exitCode: code) }
    }

    @Test func exitCodeDecidesOnlyWhenTestSegmentDecidesStatus() {
        #expect(outcome("swift test", 0) == .pass)
        #expect(outcome("swift test", 1) == .fail)
        #expect(outcome("cd /x && swift test --filter A 2>&1", 0) == .pass)
        #expect(outcome("swift build && swift test", 1) == .fail)
        #expect(outcome("set -e; swift test", 0) == .pass)
        // 다른 명령의 결과가 남는 꼴 → 결과 모름
        #expect(outcome("swift test 2>&1 | tail -5", 0) == .unknown)
        #expect(outcome("swift test | tail -5", 1) == .unknown)
        #expect(outcome("swift test; echo done", 0) == .unknown)
        #expect(outcome("swift test || true", 0) == .unknown)
        #expect(outcome("swift test &", 0) == .unknown)
        #expect(outcome("make lint || swift test", 0) == .unknown)
        #expect(outcome("swift test", nil) == .unknown)
    }

    @Test func quotedTextAndOtherCommandsAreNotVerification() {
        #expect(VerificationCommand.parse("git commit -m \"fix; swift test\"") == nil)
        #expect(VerificationCommand.parse("echo 'npm test'") == nil)
        #expect(VerificationCommand.parse("bash -c 'exit 3'") == nil)
        #expect(VerificationCommand.parse("ls tests") == nil)
        #expect(VerificationCommand.parse("bash test-fail.sh") != nil)
        #expect(VerificationCommand.parse("python3 integration/codex/test_codex_integration.py") != nil)
        #expect(VerificationCommand.parse("xcodebuild -project W.xcodeproj -scheme W -destination 'platform=macOS' build") != nil)
    }

    @Test func keysIgnoreRedirectionsAndAssignments() throws {
        let hook = try #require(VerificationCommand.parse("cd /x && CI=1 swift test --parallel 2>&1 > out.txt"))
        #expect(hook.keys == ["swift test --parallel"])
        #expect(VerificationCommand.parse("swift test --parallel")?.keys == ["swift test --parallel"])
    }

    @Test func displayMasksAssignmentValuesAndLimitsLength() {
        #expect(VerificationCommand.display("  API_TOKEN=abc123 swift test ") == "API_TOKEN=… swift test")
        #expect(VerificationCommand.display(String(repeating: "a", count: 400)).count == VerificationCommand.commandLimit)
        // 따옴표 안 `a=b`는 문자열이라 그대로, 값의 따옴표·${…}는 한 덩어리로 가린다
        let loop = #"S=/tmp/x; for c in "Debug|platform=macOS" "Release"; do cfg=${c%%|*}; xcodebuild -configuration $cfg build > $S/b.log; done"#
        #expect(VerificationCommand.display(loop)
                == #"S=…; for c in "Debug|platform=macOS" "Release"; do cfg=…; xcodebuild -configuration $cfg build > $S/b.log; done"#)
        #expect(VerificationCommand.display(#"KEY="a b" OTHER='c d' swift test"#) == "KEY=… OTHER=… swift test")
        #expect(VerificationCommand.display("xcodebuild -destination 'platform=macOS' build") == "xcodebuild -destination 'platform=macOS' build")
        #expect(VerificationCommand.display("swift test --filter=Hook") == "swift test --filter=Hook")
    }

    @Test func patternCompiles() {
        #expect(VerificationCommand.matchesPattern("swift test"))
        #expect(!VerificationCommand.matchesPattern("swiftlint"))
    }

    // 딱 300자인 명령은 줄이지 않는다.
    @Test func displayKeepsCommandExactlyAtLimit() {
        let exact = String(repeating: "a", count: VerificationCommand.commandLimit)
        #expect(VerificationCommand.display(exact) == exact)
    }

    // 큰따옴표 안의 `\"`는 따옴표를 닫지 않고, 작은따옴표 안의 역슬래시는 그냥 글자다.
    @Test func displayKeepsQuotedTextAcrossEscapedQuote() {
        #expect(VerificationCommand.display(#"echo "a\" B=1" X=2"#) == #"echo "a\" B=1" X=…"#)
        #expect(VerificationCommand.display(#"echo 'a\' X=2"#) == #"echo 'a\' X=…"#)
    }

    // 따옴표 밖의 `\"`는 따옴표를 열지 않아 뒤의 대입 값을 가린다.
    @Test func displayDoesNotOpenQuoteOnEscapedQuote() {
        #expect(VerificationCommand.display(#"echo \" A=1"#) == #"echo \" A=…"#)
    }

    // 역슬래시로 끝나는 명령도 그대로 보인다(닫히지 않은 따옴표 안이든 밖이든).
    @Test func displayKeepsTrailingBackslash() {
        #expect(VerificationCommand.display(#"echo "abc\"#) == #"echo "abc\"#)
        #expect(VerificationCommand.display(#"swift test \"#) == #"swift test \"#)
    }

    // 대입 값이 명령 끝까지 이어지면 끝까지 가린다(`$`로 끝나도).
    @Test func displayMasksValueRunningToTheEnd() {
        #expect(VerificationCommand.display("FOO=bar") == "FOO=…")
        #expect(VerificationCommand.display("A=$") == "A=…")
    }

    // 값 안의 `\"`와 `$(…)`는 한 덩어리로 가리고, `$이름`은 공백에서 끝난다.
    @Test func displayMasksEscapedQuoteAndCommandSubstitutionAsOneValue() {
        #expect(VerificationCommand.display(#"KEY="a\" b" swift test"#) == "KEY=… swift test")
        #expect(VerificationCommand.display("X=$(echo a b) swift test") == "X=… swift test")
        #expect(VerificationCommand.display("A=$HOME swift test") == "A=… swift test")
    }

    // 따옴표 안 글만 `_`로 바꾼다. 역슬래시 다음 글자는 따옴표를 여닫지 않는다.
    @Test func maskingQuotesHidesOnlyQuotedText() {
        #expect(VerificationCommand.maskingQuotes(#""a" b"#) == #""_" b"#)
        #expect(VerificationCommand.maskingQuotes(#"a\b "c\"d" e"#) == #"a\b "_\__" e"#)
        #expect(VerificationCommand.maskingQuotes(#"'a\' b"#) == #"'__' b"#)
    }

    // 따옴표로 시작하는 명령도 따옴표 안의 `;`에서 나누지 않는다.
    @Test func leadingQuoteIsNotSplitInside() throws {
        let parsed = try #require(VerificationCommand.parse(#""a; b" && swift test"#))
        #expect(parsed.segments == [#""a; b""#, "swift test"])
        #expect(parsed.connectors == ["&&"])
    }

    // `\;`는 나누지 않고 그 뒤의 `;`는 나눈다. 작은따옴표 안의 역슬래시는 따옴표를 붙잡지 않는다.
    @Test func escapedSeparatorDoesNotSplit() {
        #expect(VerificationCommand.parse(#"echo a\;b; swift test"#)?.segments == [#"echo a\;b"#, "swift test"])
        #expect(VerificationCommand.parse(#"echo 'a\'; swift test"#)?.segments == [#"echo 'a\'"#, "swift test"])
    }

    // `&>`·`<&` 리다이렉션의 `&`는 명령을 나누지 않는다.
    @Test func redirectionAmpersandDoesNotSplit() {
        #expect(outcome("swift test &> out.log", 0) == .pass)
        #expect(outcome("swift test 0<&3", 0) == .pass)
    }

    // 검증 명령 앞의 `|`·`|&`는 결과를 가리지 않는다.
    @Test func pipeBeforeVerificationStillDecides() {
        #expect(outcome("echo y | swift test", 0) == .pass)
        #expect(outcome("echo y |& swift test", 1) == .fail)
    }

    // `;`로 끝난 명령은 뒤에서 도는 명령이 아니다.
    @Test func trailingSemicolonIsNotBackground() {
        #expect(outcome("swift test;", 0) == .pass)
    }
}

/// 완료 조건별 근거 상태(SPEC 4장).
@Suite struct CardEvidenceRuleTests {
    let criteria = [Criterion("테스트 통과"), Criterion("빌드 경고 0"), Criterion("문서")]

    func agent(_ criterion: Int, _ command: String, _ outcome: CheckOutcome, at: Date, text: String? = nil) -> CheckRecord {
        CheckRecord(at: at, command: command, outcome: outcome, source: .agent, criterion: criterion,
                    criterionText: text ?? criteria[criterion].text)
    }

    func hook(_ command: String, _ outcome: CheckOutcome, at: Date) -> CheckRecord {
        CheckRecord(at: at, command: command, outcome: outcome, source: .hook)
    }

    @Test func noEvidenceIsUnverified() {
        let result = CardEvidence.evaluate(criteria: criteria, records: [], changes: [t0])
        #expect(result == Array(repeating: .unverified, count: 3))
        #expect(CardEvidence.evaluate(criteria: [], records: [hook("swift test", .pass, at: t0)], changes: []).isEmpty)
    }

    @Test func agentReportAloneIsReported() {
        let result = CardEvidence.evaluate(criteria: criteria, records: [agent(0, "swift test", .pass, at: t0)], changes: [])
        #expect(result[0].state == .passed && result[0].source == .agent)
        #expect(result[1].state == .unverified)
        #expect(EvidenceFormat.criterionLabel(result[0]) == "통과 · 보고")
    }

    @Test func matchingHookConfirms() {
        let records = [hook("cd /x && swift test 2>&1", .pass, at: t0 - 60), agent(0, "swift test", .pass, at: t0)]
        let result = CardEvidence.evaluate(criteria: criteria, records: records, changes: [])
        #expect(result[0].state == .passed && result[0].source == .hook && result[0].at == t0 - 60)
        #expect(EvidenceFormat.criterionLabel(result[0]) == "통과 · 확인됨")
    }

    @Test func hookOutsideWindowOrUnknownDoesNotConfirm() {
        let old = [hook("swift test", .pass, at: t0 - CardEvidence.confirmWindow - 1), agent(0, "swift test", .pass, at: t0)]
        #expect(CardEvidence.evaluate(criteria: criteria, records: old, changes: [])[0].source == .agent)
        let piped = [hook("swift test | tail", .unknown, at: t0 - 10), agent(0, "swift test", .pass, at: t0)]
        #expect(CardEvidence.evaluate(criteria: criteria, records: piped, changes: [])[0].source == .agent)
        let other = [hook("swift build", .pass, at: t0 - 10), agent(0, "swift test", .pass, at: t0)]
        #expect(CardEvidence.evaluate(criteria: criteria, records: other, changes: [])[0].source == .agent)
    }

    /// 보고가 통과라고 해도 훅이 본 실행이 실패면 실패.
    @Test func contradictingHookWins() {
        let records = [hook("swift test", .fail, at: t0 - 30), agent(0, "swift test", .pass, at: t0)]
        let result = CardEvidence.evaluate(criteria: criteria, records: records, changes: [])
        #expect(result[0].state == .failed && result[0].source == .hook)
    }

    @Test func laterHookRunSupersedesReport() {
        let records = [agent(0, "swift test", .pass, at: t0), hook("swift test", .fail, at: t0 + 3600)]
        #expect(CardEvidence.evaluate(criteria: criteria, records: records, changes: [])[0].state == .failed)
        let fixed = records + [hook("swift test", .pass, at: t0 + 4000)]
        #expect(CardEvidence.evaluate(criteria: criteria, records: fixed, changes: [])[0].state == .passed)
    }

    @Test func changeAfterEvidenceIsStale() {
        let records = [agent(0, "swift test", .pass, at: t0)]
        let stale = CardEvidence.evaluate(criteria: criteria, records: records, changes: [t0 - 10, t0 + 5])[0]
        #expect(stale.isStale && stale.state == .passed)
        #expect(EvidenceFormat.stateName(stale) == "변경 후 미검증")
        #expect(EvidenceFormat.criterionHelp(stale, now: t0 + 60)?.contains("이전 결과 통과") == true)
        // 같은 시각의 변경(같은 도구 호출)은 오래된 근거가 아니다
        #expect(!CardEvidence.evaluate(criteria: criteria, records: records, changes: [t0])[0].isStale)
    }

    @Test func editedCriterionDropsOldReport() {
        let records = [agent(0, "swift test", .pass, at: t0, text: "예전 조건 글")]
        #expect(CardEvidence.evaluate(criteria: criteria, records: records, changes: [])[0].state == .unverified)
    }

    @Test func skippedStaysNotPassed() {
        let records = [agent(2, "문서 확인", .skipped, at: t0)]
        let result = CardEvidence.evaluate(criteria: criteria, records: records, changes: [t0 + 1])[2]
        #expect(result.state == .skipped && !result.isStale)
    }

    /// 세션 종료·연결 해제·체크박스만으로는 통과가 되지 않는다.
    @Test func sessionEndDetachAndCheckboxDoNotPass() throws {
        let h = try HookHarness()
        let card = h.project.makeCard(in: h.context, title: "a", status: .next, criteria: criteria, at: t0)
        try h.send("doc-SessionStart", at: t0)
        let main = try #require(try h.session())
        CardLifecycle.attach(card, main, at: t0, in: h.context)
        CardEditing.setCriterion(card, at: 0, isDone: true, date: t0 + 1, in: h.context)
        try h.send("doc-SessionEnd", at: t0 + 2)
        #expect(card.criteria[0].isDone)
        #expect(CardEvidence.criteria(for: card).allSatisfy { $0.state == .unverified })
    }

    @Test func historyAndActivityShowChecks() throws {
        let (container, context) = try makeContext()
        _ = container
        let project = makeProject(context)
        let card = project.makeCard(in: context, title: "a", status: .next, criteria: criteria, at: t0)
        let event = CardEvidence.record(agent(1, "swift build", .fail, at: t0), card: card, session: nil, in: context)
        let line = try #require(CardHistoryFormat.line(for: event))
        #expect(line.text == "조건 2 검증 실패 · 보고" && line.code == "swift build")
        #expect(ActivityEntryFormat.entry(event)?.text == "swift build")
        // 옛 앱처럼 note로 읽어도 text가 없어 메모로 보이지 않는다
        #expect(event.payloadValues["text"] == nil)
    }

    // 조건 글 없이 남은 보고는 번호만 맞으면 그 조건의 근거다.
    @Test func reportWithoutCriterionTextCountsByIndex() {
        let record = CheckRecord(at: t0, command: "swift test", outcome: .pass, source: .agent, criterion: 1)
        let result = CardEvidence.evaluate(criteria: criteria, records: [record], changes: [])
        #expect(result.map(\.state) == [.unverified, .passed, .unverified])
    }

    // 보고 딱 15분 전의 훅 실행까지 보고를 확인한다.
    @Test func hookExactlyAtWindowEdgeConfirms() {
        let records = [hook("swift test", .pass, at: t0 - CardEvidence.confirmWindow), agent(0, "swift test", .pass, at: t0)]
        #expect(CardEvidence.evaluate(criteria: criteria, records: records, changes: [])[0].source == .hook)
    }

    // 근거 기록 한 건은 그 뒤의 파일 변경으로만 오래된다. 같은 시각의 변경은 아니다.
    @Test func recordIsStaleOnlyForLaterChanges() {
        let record = agent(0, "swift test", .pass, at: t0)
        #expect(!CardEvidence.isStale(record, changes: [t0 - 1, t0]))
        #expect(CardEvidence.isStale(record, changes: [t0, t0 + 1]))
    }
}
