import AppKit
import SwiftUI
import WaypointKit

/// 설정 창 「일반」 탭: 로그인할 때 열기(TRK-55), 업데이트(TRK-56). 로그인 토글은 실제 로그인 항목 상태를 따른다.
struct GeneralTab: View {
    /// 샘플 모드에서는 nil(꺼짐·비활성으로 보인다)
    @Environment(AppServices.self) private var services: AppServices?
    @State private var fallback = LoginItemController.disabled()

    private var loginItem: LoginItemController { services?.loginItem ?? fallback }

    var body: some View {
        Form {
            Section {
                LoginItemRow(controller: loginItem)
            }
            if let updater = services?.updater {
                UpdateSection(updater: updater)
            }
        }
        .formStyle(.grouped)
        .frame(width: Theme.Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 시스템 설정에서 허용하고 돌아왔을 때
            loginItem.refresh()
        }
    }
}

/// 토글 · 상태 · (승인 필요면) 시스템 설정 버튼
struct LoginItemRow: View {
    let controller: LoginItemController

    var body: some View {
        Toggle(isOn: Binding(get: { controller.status.isOn }, set: { controller.setEnabled($0) })) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("로그인할 때 열기")
                Text(statusText)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .disabled(controller.isDev)
        if controller.status == .requiresApproval {
            Button("시스템 설정에서 허용") { SystemLoginItemService.openSystemSettings() }
        }
    }

    private var statusText: String {
        if controller.failed { return "바꾸지 못함" }
        return switch controller.status {
        case .enabled: "켜짐"
        case .requiresApproval: "승인 필요"
        case .notRegistered, .notFound: "꺼짐"
        }
    }
}
