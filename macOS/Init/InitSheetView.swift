import SwiftData
import SwiftUI
import WaypointKit

/// 새 프로젝트 등록 확인: 경로, 이름·키·개요, 스택, 지침 문서·초기 카드 체크 목록, 취소·등록.
struct InitSheetView: View {
    let cancel: () -> Void
    let registered: (Project) -> Void

    @State private var form: InitForm
    @State private var error: String?
    @Environment(\.modelContext) private var context
    /// 키 중복 판정용(보관 포함)
    @Query private var projects: [Project]

    init(draft: ProjectDraft, cancel: @escaping () -> Void, registered: @escaping (Project) -> Void) {
        self.cancel = cancel
        self.registered = registered
        _form = State(initialValue: InitForm(draft: draft))
    }

    private var takenKeys: Set<String> { Set(projects.map { $0.key.uppercased() }) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Init.gap) {
            Text("새 프로젝트 등록")
                .font(Theme.pageTitle)
                .foregroundStyle(Theme.text)
            InitFields(form: $form, keyProblem: form.keyProblem(taken: takenKeys))
            InitPathStackRow(path: GuideFormat.displayPath(form.draft.rootPath), form: $form)
            HStack(alignment: .top, spacing: Theme.Init.gap) {
                InitGuideList(files: form.draft.guideFiles, checked: $form.checkedGuides)
                InitCardList(cards: form.draft.seedCards, checked: $form.checkedCards)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(Theme.Init.padding)
        .frame(minWidth: Theme.Init.windowWidth, minHeight: Theme.Init.windowHeight)
        .background(Theme.surface)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let error {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.liveText)
                    .lineLimit(2)
            }
            Spacer()
            Button("취소", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("등록", action: register)
                .keyboardShortcut(.defaultAction)
                .disabled(!form.canRegister(taken: takenKeys))
        }
        .font(Theme.body)
        .controlSize(.large)
    }

    private func register() {
        do {
            let project = try ProjectRegistry.register(form.registration, at: Date(), context: context)
            registered(project)
        } catch let failure as ProjectRegistry.Failure {
            error = Self.message(failure)
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func message(_ failure: ProjectRegistry.Failure) -> String {
        switch failure {
        case .emptyName: "이름이 비어 있음"
        case .key(.format): "키는 영문 대문자 2–5자"
        case .key(.taken): "이미 쓰는 키"
        case .folderTaken(let key): "이 폴더는 \(key)로 등록되어 있음"
        case .folderMissing: "폴더를 찾을 수 없음"
        case .guideMissing(let path): "\(path) 파일을 찾을 수 없음"
        }
    }
}
