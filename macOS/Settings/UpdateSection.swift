import SwiftUI

/// 설정 「일반」 탭의 업데이트 항목(TRK-56). 업데이트 피드가 있는 빌드에서만 보인다.
struct UpdateSection: View {
    @Bindable var updater: AppUpdater

    var body: some View {
        Section {
            Toggle("자동으로 업데이트 확인", isOn: $updater.automaticallyChecks)
            Button("지금 확인") { updater.checkNow() }
                .disabled(!updater.canCheck)
        }
    }
}
