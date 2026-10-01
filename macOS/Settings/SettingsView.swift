import SwiftUI
import WaypointKit

/// 사용량 표시 설정(`@AppStorage` 키). 사이드바 게이지와 메뉴 막대가 함께 따른다.
enum UsageSettings {
    static let showClaudeKey = "usage.showClaude"
    static let showCodexKey = "usage.showCodex"
}

/// 설정 창(⌘,)
struct SettingsView: View {
    @AppStorage(UsageSettings.showClaudeKey) private var showClaude = true
    @AppStorage(UsageSettings.showCodexKey) private var showCodex = true

    var body: some View {
        Form {
            Section("사용량") {
                Toggle(UsageGroup.Tool.claude.title, isOn: $showClaude)
                Toggle(UsageGroup.Tool.codex.title, isOn: $showCodex)
            }
        }
        .formStyle(.grouped)
        .frame(width: Theme.Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
