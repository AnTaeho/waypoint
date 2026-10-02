import SwiftUI
import WaypointKit

/// 「백업」: 머리 오른쪽 「지금 백업」, 최근 백업(시각 · 까닭 · 크기)과 줄마다 「복원…」.
struct RecordsBackupSection: View {
    let model: RecordsModel
    @State private var restoring: StoreBackup.Entry?

    var body: some View {
        Section {
            if model.backups.isEmpty {
                Text("아직 없음")
                    .foregroundStyle(Theme.Records.detail)
            }
            ForEach(model.backups, id: \.id) { entry in
                HStack {
                    Text(RecordFormat.backupLine(entry, now: Date()))
                        .monospacedDigit()
                    Spacer()
                    Button("복원…") { restoring = entry }
                }
            }
        } header: {
            HStack {
                Text("백업")
                Spacer()
                if model.isBackingUp {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Finder에서 보기") { model.showBackupsInFinder() }
                    .disabled(model.backups.isEmpty)
                Button("지금 백업") {
                    Task { await model.backUpNow() }
                }
                .disabled(model.isBackingUp || !model.canBackUp)
            }
        }
        .onAppear { model.reload() }
        .alert(
            restoring.map { "\(TimeFormat.timestamp($0.info.createdAt, now: Date())) 백업으로 되돌릴까요?" } ?? "",
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            presenting: restoring
        ) { entry in
            Button("복원하고 다시 시작") { model.restore(entry) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text(Self.restoreMessage(iCloud: AppInstance.current.cloudKitContainer() != nil))
        }
    }

    /// 복원 확인 문구. iCloud가 꺼진 실행에는 iCloud 줄을 넣지 않는다.
    static func restoreMessage(iCloud: Bool) -> String {
        var lines = ["앱을 다시 시작하며 되돌림. 지금 기록도 먼저 백업해 둠."]
        if iCloud { lines.append("iCloud가 그 뒤에 바뀐 내용을 다시 받아 올 수 있음.") }
        return lines.joined(separator: "\n")
    }
}
