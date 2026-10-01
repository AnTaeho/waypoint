import Foundation
import Testing
@testable import WaypointKit

/// 지침 문서 항목 나누기(TRK-38)
@Suite struct GuidanceItemTests {

    func parse(_ text: String, _ format: GuidanceDocumentFormat = .markdown) -> GuidanceDocument {
        let document = GuidanceDocument.parse(text, format: format)
        #expect(Array(document.joined().utf8) == Array(text.utf8))
        let failures = GuidanceItemCheck.failures(document)
        #expect(failures.isEmpty, "\(failures.map(\.description))")
        return document
    }

    @Test func emptyDocumentHasNoItems() {
        let document = parse("")
        #expect(document.items.isEmpty)
        #expect(document.ambiguity == nil)
        #expect(document.segments.isEmpty)
    }

    @Test func headingsGiveSectionPaths() {
        let document = parse("# 작업 취향\n\n## git\n- 커밋은 나눈다\n- 푸시는 모아서\n\n## 화면\n문단 첫 줄\n이어지는 줄\n")
        let kinds = document.items.map(\.kind)
        #expect(kinds == [.heading, .heading, .bullet, .bullet, .heading, .paragraph])
        #expect(document.items[0].section == [])
        #expect(document.items[1].section == ["작업 취향"])
        #expect(document.items[2].section == ["작업 취향", "git"])
        #expect(document.items[2].display == "커밋은 나눈다")
        #expect(document.items[4].section == ["작업 취향"])
        #expect(document.items[5].section == ["작업 취향", "화면"])
        #expect(document.items[5].display == "문단 첫 줄 이어지는 줄")
        #expect(document.items[5].text == "문단 첫 줄\n이어지는 줄")
    }

    @Test func rulesBetweenItemsAreNotItems() {
        let document = parse("가\n\n---\n\n나\n")
        #expect(document.items.map(\.kind) == [.paragraph, .paragraph])
        #expect(document.segments.count == 3)
    }

    @Test func nestedListsBecomeChildren() throws {
        let text = "- 하나\n  - 둘\n    - 셋\n      이어짐\n  - 둘 다음\n- 넷\n"
        let document = parse(text)
        #expect(document.items.count == 2)
        let top = document.items[0]
        #expect(top.lines == 0..<5)
        #expect(top.children.count == 2)
        #expect(top.children[0].children.count == 1)
        let third = top.children[0].children[0]
        #expect(third.id == [0, 0, 0])
        #expect(third.display == "셋 이어짐")
        #expect(document.item(id: [0, 0, 0]) == third)
        #expect(top.display == "하나")

        // 하위만 지우기
        #expect(try document.delete(third) == "- 하나\n  - 둘\n  - 둘 다음\n- 넷\n")
        // 부모를 지우면 하위도
        #expect(try document.delete(top) == "- 넷\n")
    }

    @Test func markersAreKept() {
        let document = parse("1. 첫째\n2) 둘째\n* 별\n+ 더하기\n- [x] 끝냄\n")
        #expect(document.items.map(\.marker) == ["1.", "2)", "*", "+", "-"])
        #expect(document.items.map(\.kind) == [.numbered, .numbered, .bullet, .bullet, .bullet])
        #expect(document.items[4].display == "[x] 끝냄")
    }

    @Test func listMarkersInsideCodeAreNotItems() {
        let document = parse("```sh\n- 목록 아님\n# 머리 아님\n```\n- 진짜\n  ```\n  - 안쪽 코드\n```\n  - 하위\n")
        #expect(document.items.map(\.kind) == [.code, .bullet])
        #expect(document.items[0].display == "- 목록 아님\n# 머리 아님")
        // 목록 안 코드 울타리는 닫는 줄(들여쓰지 않았어도)까지 그 항목에 든다
        #expect(document.items[1].lines == 4..<9)
        #expect(document.items[1].children.map(\.display) == ["하위"])
    }

    @Test func unindentedLineAfterListStartsParagraph() {
        let document = parse("- 항목\n문단\n")
        #expect(document.items.map(\.kind) == [.bullet, .paragraph])
    }

    @Test func tableRowsAreItems() {
        let document = parse("| 일 | 누가 |\n|---|---|\n| 판단 | Fable |\n| 손 | Opus |\n\n끝\n")
        #expect(document.items.map(\.kind) == [.tableHeader, .tableRow, .tableRow, .paragraph])
        #expect(document.items[0].lines == 0..<2)
        #expect(document.items[2].display == "| 손 | Opus |")
    }

    @Test func quoteIsOneItem() {
        let document = parse("> 첫 줄\n> 둘째 줄\n")
        #expect(document.items.map(\.kind) == [.quote])
        #expect(document.items[0].display == "첫 줄\n둘째 줄")
    }

    @Test func frontmatterIsItsOwnItem() {
        let document = parse("---\npaths: Shared/**\n---\n\n# 규칙\n- 하나\n")
        #expect(document.items.map(\.kind) == [.frontmatter, .heading, .bullet])
        #expect(document.items[0].display == "paths: Shared/**")
    }

    @Test func crlfIsKept() throws {
        let text = "# 머리\r\n\r\n- 가\r\n- 나\r\n- 다\r\n"
        let document = parse(text)
        #expect(document.items.map(\.kind) == [.heading, .bullet, .bullet, .bullet])
        #expect(document.items[1].terminator == "\r\n")
        #expect(document.items[1].text == "- 가")
        #expect(try document.delete(document.items[2]) == "# 머리\r\n\r\n- 가\r\n- 다\r\n")
        #expect(try document.replace(document.items[2], with: "- 나\n  - 새 하위") == "# 머리\r\n\r\n- 가\r\n- 나\r\n  - 새 하위\r\n- 다\r\n")
    }

    @Test func crlfLastLineWithoutNewlineFollowsPreviousLine() throws {
        let document = parse("- 가\r\n- 나")
        #expect(try document.replace(document.items[1], with: "- 나\n- 다") == "- 가\r\n- 나\r\n- 다")
    }

    @Test func byteOrderMarkStaysEditable() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("- 가\n- 나\n".utf8)
        let document = GuidanceDocument.parse(data: data, format: .markdown)
        #expect(document.isEditable)
        #expect(Array(document.joined().utf8) == Array(data))
        #expect(Array(try document.delete(document.items[1]).utf8) == Array(data.dropLast(Array("- 나\n".utf8).count)))
    }

    @Test func missingFinalNewlineIsKept() throws {
        let document = parse("- 가\n- 나")
        #expect(document.items[1].terminator == "")
        #expect(try document.delete(document.items[1]) == "- 가")
        #expect(try document.delete(document.items[0]) == "- 나")
        #expect(try document.replace(document.items[1], with: "- 다") == "- 가\n- 다")

        let withNewline = parse("- 가\n- 나\n")
        #expect(try withNewline.delete(withNewline.items[1]) == "- 가\n")
    }

    @Test func tabsKoreanAndEmojiSurviveEdits() throws {
        let text = "- 탭\t사이 🧭\n\t- 탭 들여쓰기 하위 👍🏽\n- 셋\n"
        let document = parse(text)
        #expect(document.items[0].children.count == 1)
        let replaced = try document.replace(document.items[1], with: "- 바꾼 셋 🎉")
        #expect(Array(replaced.utf8) == Array("- 탭\t사이 🧭\n\t- 탭 들여쓰기 하위 👍🏽\n- 바꾼 셋 🎉\n".utf8))
    }

    @Test func staleItemIsRejected() throws {
        let document = parse("- 가\n- 나\n")
        let other = parse("- 다른\n- 문서\n- 셋\n")
        #expect(throws: GuidanceEditError.staleItem) { try document.delete(other.items[1]) }
        #expect(throws: GuidanceEditError.staleItem) { try document.delete(other.items[2]) }
    }

    // MARK: - 애매한 문서

    @Test(arguments: [
        ("# 가\n```\n- 닫히지 않음\n", "닫히지 않은 코드 블록"),
        ("<details>\n<summary>열기</summary>\n</details>\n", "HTML 블록"),
        ("문단 첫 줄\n<!-- 주석 -->\n", "HTML 블록"),
        ("- 가\n  - 공백\n- 나\n\t- 탭\n", "탭과 공백"),
        ("- 1\n  - 2\n    - 3\n      - 4\n        - 5\n          - 6\n", "목록 중첩"),
        ("---\nname: 닫히지 않음\n\n본문\n", "frontmatter가 닫히지 않음"),
    ])
    func ambiguousDocumentIsOneItem(text: String, reason: String) throws {
        let document = parse(text)
        #expect(document.items.map(\.kind) == [.document])
        #expect(document.ambiguity?.contains(reason) == true, "\(document.ambiguity ?? "nil")")
        #expect(document.items[0].text + document.items[0].terminator == text)
        #expect(try document.delete(document.items[0]) == "")
    }

    @Test func fiveLevelsAreStillSplit() {
        let document = parse("- 1\n  - 2\n    - 3\n      - 4\n        - 5\n")
        #expect(document.ambiguity == nil)
        #expect(document.allItems.count == 5)
    }

    @Test func invalidUTF8IsNotEditable() {
        let data = Data([0x2D, 0x20, 0xFF, 0x0A])
        let document = GuidanceDocument.parse(data: data, format: .markdown)
        #expect(document.ambiguity == "UTF-8로 읽을 수 없음")
        #expect(!document.isEditable)
        #expect(throws: GuidanceEditError.notEditable) { try document.delete(document.items[0]) }
    }
}
