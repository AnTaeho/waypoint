import Testing
@testable import WaypointKit

@Suite struct MarkdownParserTests {
    func parse(_ s: String) -> [MarkdownBlock] { MarkdownParser.parse(s) }

    @Test func headings() {
        #expect(parse("# 하나\n## 둘 ##\n### 셋\n#### 넷\n#없음") == [
            .heading(level: 1, text: "하나"),
            .heading(level: 2, text: "둘"),
            .heading(level: 3, text: "셋"),
            .heading(level: 4, text: "넷"),
            .paragraph("#없음"),
        ])
    }

    @Test func paragraphsJoinLinesAndSplitOnBlank() {
        #expect(parse("첫 줄\n둘째 줄\n\n다음 문단") == [.paragraph("첫 줄 둘째 줄"), .paragraph("다음 문단")])
    }

    @Test func paragraphStopsAtOtherBlocks() {
        #expect(parse("문단\n- 항목\n# 제목") == [
            .paragraph("문단"),
            .list([MarkdownListItem(marker: .bullet, text: "항목")]),
            .heading(level: 1, text: "제목"),
        ])
    }

    @Test func listsWithMarkersCheckboxesAndDepth() {
        let blocks = parse("- 가\n* 나\n  - [ ] 할 일\n  - [x] 한 일\n1. 첫째\n2) 둘째\n  이어지는 줄")
        #expect(blocks == [.list([
            MarkdownListItem(marker: .bullet, text: "가"),
            MarkdownListItem(marker: .bullet, text: "나"),
            MarkdownListItem(marker: .bullet, text: "할 일", checked: false, depth: 1),
            MarkdownListItem(marker: .bullet, text: "한 일", checked: true, depth: 1),
            MarkdownListItem(marker: .number(1), text: "첫째"),
            MarkdownListItem(marker: .number(2), text: "둘째 이어지는 줄"),
        ])])
    }

    @Test func blankLineBetweenItemsKeepsOneList() {
        #expect(parse("- a\n\n- b\n\n문단") == [
            .list([MarkdownListItem(marker: .bullet, text: "a"), MarkdownListItem(marker: .bullet, text: "b")]),
            .paragraph("문단"),
        ])
    }

    @Test func notAList() {
        #expect(parse("-없음\n2024.9 기록") == [.paragraph("-없음 2024.9 기록")])
    }

    @Test func codeBlocksKeepContentVerbatim() {
        let text = "```swift\nlet a = 1\n\n# 제목 아님\n- 목록 아님\n```\n뒤"
        #expect(parse(text) == [
            .code(language: "swift", text: "let a = 1\n\n# 제목 아님\n- 목록 아님"),
            .paragraph("뒤"),
        ])
    }

    @Test func unclosedFenceRunsToEnd() {
        #expect(parse("~~~\na\nb") == [.code(language: nil, text: "a\nb")])
    }

    @Test func tables() {
        let text = "| 이름 | 값 | 비고 |\n|:---|:-:|--:|\n| a | `x|y` | c |\n| 짧음 |\n\n뒤"
        #expect(parse(text) == [
            .table(MarkdownTable(
                header: ["이름", "값", "비고"],
                alignments: [.leading, .center, .trailing],
                rows: [["a", "`x|y`", "c"], ["짧음", "", ""]]
            )),
            .paragraph("뒤"),
        ])
    }

    @Test func pipeWithoutSeparatorIsParagraph() {
        #expect(parse("a | b\nc") == [.paragraph("a | b c")])
    }

    @Test func quotesAndRules() {
        #expect(parse("> 인용 하나\n> 둘\n\n---\n***\n- - -") == [
            .quote("인용 하나\n둘"), .rule, .rule, .rule,
        ])
    }

    @Test func headingIndexForTableOfContents() {
        let blocks = parse("# A\n문단\n## B")
        let toc = MarkdownParser.headings(in: blocks)
        #expect(toc.map(\.index) == [0, 2])
        #expect(toc.map(\.text) == ["A", "B"])
    }

    @Test func crlf() {
        #expect(parse("# A\r\n본문\r\n") == [.heading(level: 1, text: "A"), .paragraph("본문")])
    }
}
