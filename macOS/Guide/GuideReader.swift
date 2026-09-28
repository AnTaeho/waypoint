import SwiftUI
import WaypointKit

/// 읽기: 왼쪽 목차 + 렌더링한 본문. 목차를 누르면 그 제목으로 넘어간다.
struct GuideReader: View {
    let content: String

    var body: some View {
        let blocks = MarkdownParser.parse(content)
        let toc = MarkdownParser.headings(in: blocks).filter { $0.level <= 3 }
        // GeometryReader로 감싸 본문 최소 폭(표·코드)이 분할 뷰로 번지지 않게 한다.
        GeometryReader { proxy in
            ScrollViewReader { reader in
                HStack(alignment: .top, spacing: 0) {
                    if proxy.size.width >= Theme.Guide.tocMinBodyWidth, !toc.isEmpty {
                        GuideTOC(items: toc.map { TOCItem(index: $0.index, level: $0.level, text: $0.text) }) { index in
                            withAnimation(.easeInOut(duration: 0.2)) { reader.scrollTo(index, anchor: .top) }
                        }
                        .frame(width: Theme.Guide.tocWidth)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m + 2) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                                MarkdownBlockView(block: block)
                                    .id(index)
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: Theme.Guide.readMaxWidth, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.pageH + Theme.Spacing.xs)
                        .padding(.vertical, Theme.Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

struct TOCItem: Hashable {
    let index: Int
    let level: Int
    let text: String
}

/// 목차: 「목차」 이름표 아래 제목 목록. 단계마다 조금씩 들여 쓴다.
private struct GuideTOC: View {
    let items: [TOCItem]
    let jump: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("목차")
                    .font(Theme.tableHeader)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, Theme.Spacing.s)
                ForEach(items, id: \.self) { item in
                    Button { jump(item.index) } label: {
                        Text(plain(item.text))
                            .font(item.level == 1 ? Theme.bodyMedium : Theme.body)
                            .foregroundStyle(item.level == 1 ? Theme.text : Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(max(0, item.level - 1)) * Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, Theme.Spacing.pageH)
            .padding(.trailing, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .scrollIndicators(.never)
    }

    /// 목차에는 인라인 문법 기호 없이.
    private func plain(_ text: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? text
    }
}
