import Foundation

public enum GuidanceEditError: Error, Equatable, Sendable {
    /// 이 문서에서 나온 항목이 아니거나 문서가 그 뒤 바뀌었다
    case staleItem
    /// UTF-8로 읽지 못한 원문이라 바이트 그대로 고칠 수 없다
    case notEditable
}

extension GuidanceDocument {

    /// 항목 글(`item.text`, 마지막 개행 제외)을 바꾼 새 문서. 범위 밖 바이트는 그대로다.
    /// 항목 줄이 CRLF면 바꿀 글의 `\n`도 CRLF로 맞춘다. 하위 항목이 있으면 함께 바뀐다.
    public func replace(_ item: GuidanceItem, with newText: String) throws -> String {
        try check(item)
        var replacement = newText
        if lineEndsWithCRLF(item) {
            replacement = replacement.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n")
        }
        let bytes = sourceBytes
        let result = bytes[..<item.contentRange.lowerBound] + Array(replacement.utf8) + bytes[item.contentRange.upperBound...]
        return String(decoding: result, as: UTF8.self)
    }

    /// 항목(하위 항목 포함)의 줄과 줄 끝 개행을 지운 새 문서. 빈 줄은 `deletionRange` 규칙을 따른다.
    public func delete(_ item: GuidanceItem) throws -> String {
        try check(item)
        let removed = deletionRange(item)
        let bytes = sourceBytes
        return String(decoding: bytes[..<removed.lowerBound] + bytes[removed.upperBound...], as: UTF8.self)
    }

    /// 지울 바이트 범위. 항목 줄 전체(마지막 개행 포함)에 더해:
    /// - 앞이 빈 줄(또는 문서 처음)이고 뒤도 빈 줄이면 뒤 빈 줄 하나를 함께 지운다(빈 줄 두 개가 겹치지 않게).
    /// - 앞이 빈 줄이고 뒤가 문서 끝이면 앞 빈 줄 하나를 함께 지운다.
    /// - 지운 뒤가 문서 끝이고 원문 끝에 개행이 없었으면 앞 줄의 개행도 지워 「끝 개행 없음」을 지킨다.
    /// 목록 가운데 항목처럼 앞뒤가 빈 줄이 아니면 항목 줄만 지운다.
    func deletionRange(_ item: GuidanceItem) -> Range<Int> {
        let lines = lineTable
        let first = item.lines.lowerBound
        let last = item.lines.upperBound - 1
        let bytes = sourceBytes
        func isBlank(_ index: Int) -> Bool {
            bytes[lines[index].start..<lines[index].contentEnd].allSatisfy { $0 == 0x20 || $0 == 0x09 }
        }
        var startLine = first
        var endLine = last
        let prevBlank = first == 0 || isBlank(first - 1)
        let next = last + 1
        if next < lines.count, isBlank(next), prevBlank {
            endLine = next
        } else if next == lines.count, first > 0, isBlank(first - 1) {
            startLine = first - 1
        }
        var lower = lines[startLine].start
        let upper = lines[endLine].end
        let endsWithoutNewline = lines[lines.count - 1].end == lines[lines.count - 1].contentEnd
        if upper == bytes.count, endsWithoutNewline, startLine > 0 {
            lower = lines[startLine - 1].contentEnd
        }
        return lower..<upper
    }

    /// 항목 첫 줄의 개행 모양. 개행이 없는 마지막 줄이면 바로 앞 줄을 본다.
    private func lineEndsWithCRLF(_ item: GuidanceItem) -> Bool {
        var index = item.lines.lowerBound
        if lineTable[index].end == lineTable[index].contentEnd, index > 0 { index -= 1 }
        return lineTable[index].end - lineTable[index].contentEnd == 2
    }

    private func check(_ item: GuidanceItem) throws {
        guard isEditable else { throw GuidanceEditError.notEditable }
        guard let found = self.item(id: item.id), found.range == item.range, found.text == item.text,
              Array(found.text.utf8) == Array(item.text.utf8)
        else { throw GuidanceEditError.staleItem }
    }
}
