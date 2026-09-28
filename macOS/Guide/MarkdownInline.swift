import SwiftUI

/// 인라인 Markdown(굵게·기울임·코드·링크)을 글자 모양으로 푼다. 굵게는 나눔스퀘어라운드 B, 코드는 모노.
enum MarkdownInline {
    static func text(_ source: String, size: CGFloat = Theme.Guide.bodySize, bold: Bool = false) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        let base = Theme.rounded(size, bold ? .bold : .regular)
        for run in result.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                result[run.range].font = .system(size: size - 1, design: .monospaced)
                result[run.range].backgroundColor = Theme.bgSunken
            } else if intent.contains(.stronglyEmphasized) {
                result[run.range].font = Theme.rounded(size, .bold)
            } else {
                result[run.range].font = base
            }
            if run.link != nil {
                result[run.range].foregroundColor = Theme.liveText
            }
        }
        return result
    }
}
