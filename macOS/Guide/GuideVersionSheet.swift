import SwiftData
import SwiftUI
import WaypointKit

/// 지난 버전 원문(읽기 전용)과 되돌리기.
struct GuideVersionSheet: View {
    let doc: GuideDoc
    let version: GuideVersion

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text(TimeFormat.timestamp(version.at, now: Date(), seconds: true))
                    .font(Theme.sectionLarge)
                Text(GuideFormat.sourceName(version.source))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .foregroundStyle(Theme.text)
            ScrollView {
                Text(version.content)
                    .font(Theme.Guide.source)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.m)
            }
            .background(Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
            }
            HStack {
                if let error {
                    Text(error).font(Theme.caption).foregroundStyle(Theme.liveText)
                }
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("이 버전으로 되돌리기", action: revert)
                    .disabled(version.content == doc.content && doc.draft == nil)
            }
            .font(Theme.body)
        }
        .padding(Theme.Spacing.xl)
        .frame(
            minWidth: Theme.Guide.versionSheetWidth.lowerBound, idealWidth: Theme.Guide.versionSheetWidth.upperBound,
            minHeight: Theme.Guide.versionSheetHeight.lowerBound, idealHeight: Theme.Guide.versionSheetHeight.upperBound
        )
        .background(Theme.bg)
    }

    private func revert() {
        do {
            _ = try GuideLibrary.revert(doc, to: version, at: Date(), context: context)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
