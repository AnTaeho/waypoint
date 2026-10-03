import SwiftUI
import WaypointKit

/// 사용량 표시 설정(`@AppStorage` 키). 사이드바 게이지와 메뉴 막대가 함께 따른다.
enum UsageSettings {
    static let showClaudeKey = "usage.showClaude"
    static let showCodexKey = "usage.showCodex"
}

/// 설정 창 탭. 고른 탭은 `WaypointSettingsTab`에 남는다(실행 인자 `-WaypointSettingsTab general|usage|records`로도 고른다).
enum SettingsTab: String {
    case general, usage, records

    static let storageKey = "WaypointSettingsTab"
}

/// 설정 창(⌘,): 일반 · 사용량 · 기록
struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab()
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            UsageSettingsTab()
                .tabItem { Label("사용량", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(SettingsTab.usage)
            RecordsTab()
                .tabItem { Label("기록", systemImage: "externaldrive") }
                .tag(SettingsTab.records)
        }
    }
}

/// 「사용량」 탭
struct UsageSettingsTab: View {
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
