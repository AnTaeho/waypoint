import Foundation
import Testing
@testable import WaypointKit

/// 지침 항목 속성 검사: 다시 합치기·항목 범위·지우기·바꾸기.
enum GuidanceItemCheck {

    struct Failure: CustomStringConvertible {
        var item: [Int]
        var what: String
        var description: String { "항목 \(item): \(what)" }
    }

    static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    /// 줄 내용 바이트(개행 제외). 글자 비교(정규화)를 피하려고 바이트로 비교한다.
    static func lineContents(_ bytes: [UInt8]) -> [ArraySlice<UInt8>] {
        guard !bytes.isEmpty else { return [] }
        var lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        if bytes.last == 0x0A { lines.removeLast() }
        return lines.map { $0.last == 0x0D ? $0.dropLast() : $0 }
    }

    /// 실패 목록(빈 배열이면 통과). 메시지에 문서 내용을 넣지 않는다.
    static func failures(_ document: GuidanceDocument, replacement: String = "⟦바꿈⟧\n둘째 줄") -> [Failure] {
        var result: [Failure] = []
        let original = bytes(document.source)
        if bytes(document.joined()) != original { result.append(Failure(item: [], what: "다시 합친 결과가 원문과 다름")) }
        let originalLines = lineContents(original)

        for item in document.allItems {
            func fail(_ what: String) { result.append(Failure(item: item.id, what: what)) }
            guard item.range.upperBound <= original.count,
                  Array(original[item.range]) == bytes(item.raw) else { fail("범위와 원문이 다름"); continue }
            for child in item.children where !(item.range.lowerBound <= child.range.lowerBound
                                                && child.range.upperBound <= item.range.upperBound) {
                fail("하위 항목 \(child.id)가 범위 밖")
            }

            // 바꾸기: 글 자리 밖 바이트는 그대로
            if let same = try? document.replace(item, with: item.text), bytes(same) != original {
                fail("같은 글로 바꿨는데 원문이 바뀜")
            }
            if let replaced = try? document.replace(item, with: replacement) {
                let new = bytes(replaced)
                let prefix = Array(original[..<item.contentRange.lowerBound])
                let suffix = Array(original[item.contentRange.upperBound...])
                if !(new.starts(with: prefix) && new.reversed().starts(with: suffix.reversed())
                     && new.count >= prefix.count + suffix.count) {
                    fail("바꾸기가 범위 밖 바이트를 바꿈")
                }
            } else {
                fail("바꾸기 실패")
            }

            // 지우기: 지운 범위 = 항목 줄 ± 빈 줄 하나 ± 앞 줄 개행, 나머지 줄은 그대로
            guard let deleted = try? document.delete(item) else { fail("지우기 실패"); continue }
            let removed = document.deletionRange(item)
            if bytes(deleted) != Array(original[..<removed.lowerBound]) + Array(original[removed.upperBound...]) {
                fail("지운 결과가 지운 범위와 맞지 않음")
            }
            if !(removed.lowerBound <= item.range.lowerBound && removed.upperBound >= item.range.upperBound) {
                fail("지운 범위가 항목을 덮지 않음")
            }
            var outside = originalLines
            outside.removeSubrange(item.lines)
            let after = lineContents(bytes(deleted))
            if after != outside {
                // 빈 줄 하나만 빠졌는지: 처음 어긋난 자리가 빈 줄이고, 그 뒤가 한 칸씩 같아야 한다
                let k = (0..<min(outside.count, after.count)).first { outside[$0] != after[$0] } ?? after.count
                let collapsed = after.count == outside.count - 1
                    && outside[k].allSatisfy { $0 == 0x20 || $0 == 0x09 }
                    && Array(outside[(k + 1)...]) == Array(after[k...])
                if !collapsed { fail("항목 밖 줄이 바뀜") }
            }
        }
        return result
    }
}
