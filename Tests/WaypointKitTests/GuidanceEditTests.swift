import Foundation
import Testing
@testable import WaypointKit

/// 항목 지우기의 빈 줄 규칙, 기억·색인·명령 규칙 나누기, 픽스처 속성 검사(TRK-38)
@Suite struct GuidanceEditTests {

    func parse(_ text: String, _ format: GuidanceDocumentFormat = .markdown) -> GuidanceDocument {
        let document = GuidanceDocument.parse(text, format: format)
        let failures = GuidanceItemCheck.failures(document)
        #expect(failures.isEmpty, "\(failures.map(\.description))")
        return document
    }

    // MARK: - 빈 줄 규칙

    @Test func middleListItemLeavesBlankLinesAlone() throws {
        let document = parse("# 가\n\n- 하나\n- 둘\n- 셋\n\n끝\n")
        #expect(try document.delete(document.items[2]) == "# 가\n\n- 하나\n- 셋\n\n끝\n")
    }

    @Test func lastParagraphOfSectionCollapsesBlankLines() throws {
        let document = parse("# 가\n\n문단\n\n# 나\n")
        #expect(try document.delete(document.items[1]) == "# 가\n\n# 나\n")
    }

    @Test func looseListMiddleItemCollapsesBlankLines() throws {
        let document = parse("- 하나\n\n- 둘\n\n- 셋\n")
        #expect(try document.delete(document.items[1]) == "- 하나\n\n- 셋\n")
    }

    @Test func firstItemTakesFollowingBlankLine() throws {
        let document = parse("# 머리\n\n본문\n")
        #expect(try document.delete(document.items[0]) == "본문\n")
    }

    @Test func lastItemTakesPrecedingBlankLine() throws {
        let document = parse("가\n\n나\n")
        #expect(try document.delete(document.items[1]) == "가\n")
        let noNewline = parse("가\n\n나")
        #expect(try noNewline.delete(noNewline.items[1]) == "가")
    }

    @Test func itemBetweenTextKeepsNeighbours() throws {
        let document = parse("가\n\n나\n- 목록\n")
        // 앞이 빈 줄이어도 뒤가 빈 줄이 아니면 항목 줄만
        #expect(try document.delete(document.items[1]) == "가\n\n- 목록\n")
    }

    @Test func replacingWithEmptyTextLeavesEmptyLine() throws {
        let document = parse("- 가\n- 나\n")
        #expect(try document.replace(document.items[0], with: "") == "\n- 나\n")
    }

    // MARK: - 기억

    @Test func memoryFileIsOneItem() throws {
        let text = "---\nname: 짧은 이름\ndescription: \"한 줄 설명\"\nmetadata:\n  type: feedback\n---\n\n본문 첫 줄\n**Why:** 이유\n"
        let document = parse(text, .memory)
        #expect(document.items.count == 1)
        let item = document.items[0]
        #expect(item.kind == .memory)
        #expect(item.memory == GuidanceMemoryFields(name: "짧은 이름", description: "한 줄 설명", type: "feedback"))
        #expect(item.display == "한 줄 설명")
        #expect(item.raw == text)

        let topType = parse("---\nname: a\ntype: project\n---\n본문\n", .memory)
        #expect(topType.items[0].memory?.type == "project")

        let plain = parse("머리 없는 기억\n", .memory)
        #expect(plain.items[0].memory == GuidanceMemoryFields())
        #expect(plain.items[0].display == "머리 없는 기억")
    }

    @Test func memoryIndexPairsWithFiles() {
        let index = parse("""
        # 기억

        - [진행 상태](progress.md) — 다음 할 일
        - [빠진 파일](missing.md) — 짝 없음
        * [하위 폴더](./notes/style.md#절) — 이름으로 짝
        - 링크 없는 줄

        """, .memoryIndex)
        #expect(index.items.map(\.kind) == [.heading, .indexEntry, .indexEntry, .indexEntry, .bullet])
        #expect(index.items[1].link == "progress.md")
        let pairing = MemoryIndexPairing(index: index, files: ["MEMORY.md", "progress.md", "style.md", "lonely.md"])
        #expect(pairing.pairs.map(\.file) == ["progress.md", "style.md"])
        #expect(pairing.pairs.map(\.entry) == [[1], [3]])
        #expect(pairing.orphanEntries == [[2]])
        #expect(pairing.unindexedFiles == ["lonely.md"])
    }

    // MARK: - Codex 명령 규칙

    @Test func commandRulesAreOnePerRule() throws {
        let text = """
        # 주석은 항목이 아니다
        prefix_rule(pattern=["git", "status"], decision="allow")

        prefix_rule(pattern=["sh", "-c", "echo ')' # 문자열 안"], decision="allow")  # 끝 주석 (
        prefix_rule(
            pattern = ["rm", "-rf"],
            decision = "forbidden",
        )
        prefix_rule(pattern=["x\\"(y"], decision="allow")
        """
        let document = parse(text, .commandRules)
        #expect(document.ambiguity == nil)
        #expect(document.items.map(\.lines) == [1..<2, 3..<4, 4..<8, 8..<9])
        #expect(document.items[2].display == "prefix_rule( pattern = [\"rm\", \"-rf\"], decision = \"forbidden\", )")
        #expect(try document.delete(document.items[0]) == text.replacingOccurrences(of: "prefix_rule(pattern=[\"git\", \"status\"], decision=\"allow\")\n", with: ""))
    }

    @Test(arguments: ["prefix_rule(pattern=[\"a\"]\n", "prefix_rule(\"a\"))\n"])
    func unbalancedRulesAreAmbiguous(text: String) {
        let document = parse(text, .commandRules)
        #expect(document.items.map(\.kind) == [.document])
    }

    // MARK: - 픽스처

    @Test(arguments: [
        ("claude-example.md", GuidanceDocumentFormat.markdown), ("agents-example.md", .markdown), ("rules-frontmatter.md", .markdown),
        ("memory-feedback.md", .memory), ("MEMORY.md", .memoryIndex), ("default.rules", .commandRules),
    ])
    func fixturesRoundTrip(name: String, format: GuidanceDocumentFormat) throws {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/guidance"))
        let data = try Data(contentsOf: url)
        let document = GuidanceDocument.parse(data: data, format: format)
        #expect(document.ambiguity == nil)
        #expect(Array(document.joined().utf8) == Array(data))
        #expect(document.allItems.count > 1 || format == .memory)
        let failures = GuidanceItemCheck.failures(document)
        #expect(failures.isEmpty, "\(failures.map(\.description))")
    }
}
