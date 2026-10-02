import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WaypointKit

/// 「내보내기·지우기」: 전체 내보내기 · 프로젝트 하나 내보내기 · 오른쪽 붉은 「모든 기록 지우기…」(확인 두 번).
struct RecordsDataSection: View {
    let model: RecordsModel
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var wipeStep: WipeStep?

    enum WipeStep: Identifiable {
        case first
        case confirm(RecordWipe.Counts)

        var id: String {
            switch self {
            case .first: "first"
            case .confirm: "confirm"
            }
        }
    }

    var body: some View {
        Section("내보내기·지우기") {
            HStack {
                Button("전체 내보내기…") { save(project: nil) }
                Menu("프로젝트 하나 내보내기…") {
                    ForEach(projects) { project in
                        Button("\(project.key) · \(project.name)") { save(project: project) }
                    }
                }
                .fixedSize()
                .disabled(projects.isEmpty)
                Spacer()
                Button("모든 기록 지우기…") { wipeStep = .first }
                    .foregroundStyle(Theme.Records.destructive)
                    .disabled(!model.canBackUp)
            }
            if let notice = model.notice {
                Text(notice.text)
                    .font(Theme.Records.detailFont)
                    .foregroundStyle(notice.isError ? Theme.Records.destructive : Theme.Records.detail)
            }
        }
        .alert("모든 기록을 지울까요?", isPresented: binding(for: "first")) {
            Button("계속") { wipeStep = .confirm(model.counts()) }
            Button("취소", role: .cancel) {}
        } message: {
            Text(Self.firstMessage(iCloud: AppInstance.current.cloudKitContainer() != nil))
        }
        .alert(confirmCounts.map { RecordFormat.wipeSummary($0) + "를 지울까요?" } ?? "",
               isPresented: binding(for: "confirm"), presenting: confirmCounts) { _ in
            Button("지우기", role: .destructive) { model.wipeAll() }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("지우기 전에 백업해 두고, 지운 뒤 다시 시작함.")
        }
    }

    private var confirmCounts: RecordWipe.Counts? {
        if case .confirm(let counts) = wipeStep { counts } else { nil }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { wipeStep?.id == id }, set: { if !$0, wipeStep?.id == id { wipeStep = nil } })
    }

    /// 첫 확인 문구. iCloud가 꺼진 실행에는 iPhone 줄을 넣지 않는다.
    static func firstMessage(iCloud: Bool) -> String {
        var lines = ["프로젝트·카드·세션·요청 문장·지침 문서가 모두 지워짐. 백업은 남음."]
        if iCloud { lines.append("iCloud로 이어진 iPhone에서도 지워짐.") }
        return lines.joined(separator: "\n")
    }

    private func save(project: Project?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = RecordExport.suggestedFileName(project: project)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(project: project, to: url)
    }
}
