import Foundation
import Testing
@testable import WaypointKit

@Suite struct ProjectKeyTests {
    @Test func format() {
        #expect(ProjectKey.isValidFormat("LD"))
        #expect(ProjectKey.isValidFormat("ABCDE"))
        #expect(!ProjectKey.isValidFormat("A"))
        #expect(!ProjectKey.isValidFormat("ABCDEF"))
        #expect(!ProjectKey.isValidFormat("ldg"))
        #expect(!ProjectKey.isValidFormat("LD1"))
        #expect(!ProjectKey.isValidFormat("LD-G"))
        #expect(!ProjectKey.isValidFormat("ÄBC"))
        #expect(!ProjectKey.isValidFormat("가계"))
    }

    @Test func normalizeUppercasesAndTrims() {
        #expect(ProjectKey.normalize("  ldg ") == "LDG")
        #expect(ProjectKey.normalize("wIp") == "WIP")
        // 글자를 버리지 않는다(규칙 위반은 problem이 알린다)
        #expect(ProjectKey.normalize("ld-1") == "LD-1")
    }

    @Test func problem() {
        let taken: Set<String> = ["TRK", "PRB"]
        #expect(ProjectKey.problem("LDG", taken: taken) == nil)
        #expect(ProjectKey.problem("PRB", taken: taken) == .taken)
        #expect(ProjectKey.problem("P", taken: taken) == .format)
        #expect(ProjectKey.problem("prb", taken: taken) == .format)
    }

    @Test func suggestFromName() {
        #expect(ProjectKey.suggest(name: "Waypoint Init Probe", folder: "x", taken: []) == "WIP")
        #expect(ProjectKey.suggest(name: "ledger", folder: "x", taken: []) == "LDG")
        #expect(ProjectKey.suggest(name: "noteCli", folder: "x", taken: []) == "NC")
        // 한글 이름이면 폴더 이름으로
        #expect(ProjectKey.suggest(name: "가계부 앱", folder: "waypoint-init-probe", taken: []) == "WIP")
        // 영문이 전혀 없으면 PRJ
        #expect(ProjectKey.suggest(name: "가계부", folder: "가계부", taken: []) == "PRJ")
    }

    @Test func suggestAvoidsTaken() {
        // 머리글자가 쓰이면 다음 후보(자음 키)
        #expect(ProjectKey.suggest(name: "Waypoint Init Probe", folder: "x", taken: ["WIP"]) == "WYP")
        // 후보가 모두 쓰이면 변형
        let taken: Set<String> = ["LDG", "LED", "PRJ"]
        let key = ProjectKey.suggest(name: "ledger", folder: "ledger", taken: taken)
        #expect(key == "LDGA")
        #expect(ProjectKey.problem(key, taken: taken) == nil)
        // 결과는 늘 규칙에 맞고 겹치지 않는다
        var all = Set<String>()
        for _ in 0..<40 {
            let next = ProjectKey.suggest(name: "ledger", folder: "ledger", taken: all)
            #expect(ProjectKey.problem(next, taken: all) == nil)
            all.insert(next)
        }
        #expect(all.count == 40)
    }

    @Test func words() {
        #expect(ProjectKey.words(in: "waypoint-init_probe") == ["WAYPOINT", "INIT", "PROBE"])
        #expect(ProjectKey.words(in: "myCLITool") == ["MY", "CLITOOL"])
        #expect(ProjectKey.consonantKey("LEDGER") == "LDG")
        #expect(ProjectKey.consonantKey("AUE") == "AUE")
    }
}
