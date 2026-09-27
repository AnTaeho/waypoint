import SwiftUI
import WaypointKit

/// 프로젝트 보드. M1 3단계에서 채운다(아이디어·나중에 / 다음 할 일 / 작업중 / 완료).
struct ProjectBoardView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(project.name)
                .font(Theme.pageTitle)
                .foregroundStyle(Theme.text)
            Text(project.rootPath)
                .font(Theme.mono)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, Theme.Spacing.pageH)
        .padding(.vertical, Theme.Spacing.pageV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .navigationTitle(project.name)
    }
}
