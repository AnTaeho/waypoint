import SwiftUI
import WaypointKit

/// 지운 파일(사본만 남은 경로)을 골랐을 때: 경로 · 「없는 파일」 한 줄, 아래 사본 목록과 되돌리기.
struct GuidanceDeletedDetail: View {
    let path: String
    @Environment(\.guidanceFiles) private var files

    var body: some View {
        let backups = files.backups?.backups(of: path) ?? []
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.m) {
                Text(GuideFormat.displayPath(path))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.Spacing.m)
                Text("없는 파일 · 백업 \(backups.count)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.pageH)
            .frame(height: Theme.Size.rowHeight)
            .background(Theme.bgPanel)
            Divider().overlay(Theme.divider)
            GuidanceBackupBrowser(path: path, backups: backups) {}
                .padding(.horizontal, Theme.Spacing.pageH)
                .padding(.vertical, Theme.Spacing.l)
                .id(path)
        }
    }
}
