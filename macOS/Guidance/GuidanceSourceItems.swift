import SwiftData
import SwiftUI
import WaypointKit

/// 지침 화면의 항목 보기. 프로젝트 안 지침 파일은 지침 문서로(처음 고치면 등록), 프로젝트 밖 파일은 파일 그대로 쓴다.
/// 등록 문서는 앱 기록을 바탕으로 하고, 충돌이면 지침 문서 화면과 같은 비교 화면을 보인다.
/// 파일 대상은 UTF-8 그대로 다시 읽은 원문을 바탕으로 하고, 쓴 뒤·「다시 읽기」에 다시 읽는다.
struct GuidanceSourceItems: View {
    let source: GuidanceSource
    /// 보기용으로 읽은 내용(앞부분만, 깨진 바이트는 대체 문자)
    let text: String
    let format: GuidanceDocumentFormat

    @Query private var projects: [Project]
    /// 등록 전 파일의 원문(UTF-8 그대로 전부). 못 읽으면 nil이고 보기만 한다.
    @State private var exact: String?
    /// 올리면 파일을 다시 읽는다
    @State private var loads = 0

    var body: some View {
        let target = GuideItemTarget.resolve(source, projects: projects)
        Group {
            if case .registered(let doc) = target, let local = doc.conflictContent {
                GuideConflictView(doc: doc, local: local) {}
            } else {
                // 한 자리에 두어 처음 고쳐 등록돼도 화면 상태(지움 알림)가 이어진다
                let (content, writer) = contentAndWriter(for: target)
                GuidanceItemsView(content: content, format: format, writer: writer)
            }
        }
        // 파일이 바뀌면(크기·수정 시각) 다시 읽는다.
        .task(id: LoadKey(source: source, loads: loads)) {
            exact = try? GuideFile.read(URL(fileURLWithPath: source.path)).content
        }
    }

    private func contentAndWriter(for target: GuideItemTarget) -> (String, GuidanceItemWriter?) {
        switch target {
        case .registered(let doc): (doc.content, GuidanceItemWriter(target: target))
        case .registerable: exact.map { ($0, GuidanceItemWriter(target: target)) } ?? (text, nil)
        case .file: exact.map { ($0, GuidanceItemWriter(target: target, reload: { loads += 1 })) } ?? (text, nil)
        case .readOnly: (text, nil)
        }
    }

    private struct LoadKey: Hashable {
        var source: GuidanceSource
        var loads: Int
    }
}
