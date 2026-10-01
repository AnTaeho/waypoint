import SwiftData
import SwiftUI
import WaypointKit

/// 카드 상세 본문: 경로, 상태·종류 배지, 제목, 본문(Markdown), 완료 조건, 히스토리.
/// 곁들이는 정보(프로젝트·세션·변경 파일·연결된 카드·메모)는 인스펙터(`CardInspector`)에 있다.
struct CardDetailView: View {
    let card: Card
    @Environment(\.modelContext) private var context

    var body: some View {
        LiveDataTimeline { now in
            // GeometryReader로 감싸 본문이 분할 뷰에 최소 폭을 요구하지 않게 한다.
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        CardDetailHeader(card: card, now: now) { moveToDone() }
                        CardResumeSection(card: card)
                        if !card.body.isEmpty {
                            CardMarkdownText(markdown: card.body)
                        }
                        if !card.criteria.isEmpty {
                            CardCriteriaView(card: card, evidence: CardEvidence.criteria(for: card), now: now) {
                                setCriterion($0, $1)
                            }
                        }
                        CardChecksView(records: CardEvidence.records(for: card),
                                       changes: CardEvidence.changeTimes(for: card), now: now)
                        CardHistoryView(lines: CardHistoryFormat.lines(for: card), now: now)
                    }
                    .padding(.horizontal, Theme.Spacing.pageH)
                    .padding(.vertical, Theme.Spacing.pageV)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle(card.displayID)
    }

    private func moveToDone() {
        CardEditing.completeAndSave(card, at: Date(), in: context)
    }

    private func setCriterion(_ index: Int, _ isDone: Bool) {
        CardEditing.setCriterionAndSave(card, at: index, isDone: isDone, date: Date(), in: context)
    }
}

/// 카드 본문 Markdown. 줄바꿈을 살린 인라인 문법(굵게·기울임·코드·링크)까지 보인다.
private struct CardMarkdownText: View {
    let markdown: String

    var body: some View {
        Text(attributed)
            .font(Theme.detailBody)
            .foregroundStyle(Theme.text)
            .lineSpacing(Theme.Spacing.xs + 1)
            .textSelection(.enabled)
            .frame(maxWidth: Theme.Size.detailBodyMaxWidth, alignment: .leading)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}
