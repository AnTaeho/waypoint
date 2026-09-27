import SwiftUI

// macOS 루트 화면. M0에서는 빈 창.
struct RootView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 480, minHeight: 320)
    }
}
