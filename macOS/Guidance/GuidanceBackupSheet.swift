import SwiftUI
import WaypointKit

/// 「백업 N」 창: 왼쪽 사본 목록(시각 · 까닭), 오른쪽 고른 사본 원문, 아래 「이 판으로 되돌리기」.
struct GuidanceBackupSheet: View {
    let path: String
    let backups: [GuidanceBackupStore.Backup]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(GuideFormat.displayPath(path))
                .font(Theme.mono)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            GuidanceBackupBrowser(path: path, backups: backups, close: { dismiss() }) { dismiss() }
        }
        .padding(Theme.Spacing.xl)
        .frame(
            minWidth: Theme.Guide.versionSheetWidth.lowerBound, idealWidth: Theme.Guide.versionSheetWidth.upperBound,
            minHeight: Theme.Guide.versionSheetHeight.lowerBound, idealHeight: Theme.Guide.versionSheetHeight.upperBound
        )
        .background(Theme.bg)
    }
}

/// 사본 목록 + 원문 + 되돌리기. 지침 화면의 지운 파일 자리와 「백업 N」 창이 같이 쓴다.
struct GuidanceBackupBrowser: View {
    let path: String
    let backups: [GuidanceBackupStore.Backup]
    /// 창이면 「닫기」
    var close: (() -> Void)?
    /// 되돌린 뒤
    let restored: () -> Void

    @Environment(\.guidanceFiles) private var files
    @State private var selected: GuidanceBackupStore.Backup?
    @State private var text: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                list
                    .frame(width: Theme.Guidance.backupListWidth)
                ScrollView {
                    Text(text ?? "")
                        .font(Theme.Guide.source)
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(Theme.Spacing.m)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
                }
            }
            HStack {
                if let error {
                    Text(error).font(Theme.caption).foregroundStyle(Theme.liveText)
                }
                Spacer()
                if let close {
                    Button("닫기", action: close)
                        .keyboardShortcut(.cancelAction)
                }
                Button("이 판으로 되돌리기", action: restore)
                    .disabled(selected == nil)
            }
            .font(Theme.body)
        }
        .task(id: selected) {
            guard let selected else { return }
            text = (try? files.backups?.content(of: selected)).map { String(decoding: $0, as: UTF8.self) }
        }
        .onAppear { if selected == nil { selected = backups.first } }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(backups) { backup in
                    Button { selected = backup } label: {
                        HStack {
                            Text(TimeFormat.timestamp(backup.at, now: Date(), seconds: true))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(GuidanceBackupFormat.reasonName(backup.reason))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .font(Theme.body)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(selected == backup ? Theme.GuideItems.hoverBg : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.row))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 지금 파일을 먼저 백업하고 이 사본으로 되돌린다.
    private func restore() {
        guard let selected, let store = files.backups else { return }
        do {
            try GuidanceFileWrite.restore(selected, backups: store, at: Date())
            error = nil
            files.didWrite()
            restored()
        } catch {
            self.error = GuidanceFileRunner.message(error)
        }
    }
}
