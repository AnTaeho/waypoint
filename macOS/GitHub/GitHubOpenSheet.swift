import SwiftUI
import WaypointKit

/// 「이슈 열기…」「PR 열기…」 시트. 카드 내용으로 채워 두고 고칠 수 있다.
struct GitHubOpenSheet: View {
    let card: Card
    let kind: GitHubKind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppServices.self) private var services: AppServices?
    @State private var draft = GitHubDraft(kind: .issue, title: "")
    @State private var options: GitHubOptions?
    @State private var base = ""
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("\(card.displayID) · \(kind.name) 열기").font(Theme.pageTitle).lineLimit(2)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.m) {
                GridRow {
                    label("저장소")
                    Text(options?.repo ?? "").font(Theme.mono).textSelection(.enabled)
                }
                GridRow {
                    label("제목")
                    TextField("제목", text: $draft.title).textFieldStyle(.roundedBorder).labelsHidden()
                }
                GridRow(alignment: .top) {
                    label("본문")
                    TextEditor(text: $draft.body).font(Theme.mono)
                        .frame(height: Theme.GitHub.bodyHeight)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.row)
                                .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
                        }
                }
                if kind == .pr { GitHubBranchRows(draft: $draft, base: $base, options: options, label: label) }
            }
            HStack(spacing: Theme.Spacing.m) {
                if working { ProgressView().controlSize(.small) }
                if let failure {
                    Text(failure).font(Theme.captionLarge).foregroundStyle(Theme.liveText)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("열기") { open() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!canOpen)
            }
        }
        .padding(Theme.Spacing.pageH)
        .frame(width: Theme.GitHub.sheetWidth)
        .background(Theme.bg)
        .onAppear(perform: fill)
    }

    private var canOpen: Bool {
        let titled = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !working && titled && options != nil && (kind == .issue || draft.head != nil)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.body).foregroundStyle(Theme.textMuted)
            .frame(width: Theme.GitHub.labelWidth, alignment: .leading)
    }

    private func fill() {
        draft = GitHubLog.draft(for: card, kind: kind)
        guard let project = card.project else { return }
        do {
            let read = try GitHubOptions.read(rootPath: project.rootPath)
            options = read
            if kind == .pr {
                draft.head = read.currentBranch ?? read.branches.first
                if read.branches.isEmpty { failure = GitHubError.noBranch.message }
            }
        } catch {
            failure = (error as? GitHubError)?.message
        }
    }

    private func open() {
        guard let services else { return }
        var request = draft
        request.base = base
        working = true
        failure = nil
        Task {
            let error = await services.github.open(request, card: card, in: context)
            working = false
            if let error { failure = error.message } else { dismiss() }
        }
    }
}

/// PR에만 있는 줄: 올릴 브랜치, 합칠 브랜치, 초안.
struct GitHubBranchRows<Label: View>: View {
    @Binding var draft: GitHubDraft
    @Binding var base: String
    let options: GitHubOptions?
    let label: (String) -> Label

    var body: some View {
        GridRow {
            label("브랜치")
            Picker("브랜치", selection: $draft.head) {
                ForEach(options?.branches ?? [], id: \.self) { Text($0).tag(Optional($0)) }
            }
            .labelsHidden().fixedSize()
        }
        GridRow {
            label("합칠 곳")
            TextField(options?.defaultBranch ?? "기본 브랜치", text: $base).textFieldStyle(.roundedBorder).labelsHidden()
        }
        GridRow {
            label("")
            Toggle("초안으로 열기", isOn: $draft.isDraft)
        }
    }
}
