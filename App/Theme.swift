import SwiftUI

/// DESIGN.md 토큰. 뷰는 색·폰트·간격·모서리를 여기서만 가져온다.
enum Theme {

    // MARK: 색

    static let bg = Color(hex: 0xFAF9F5)
    static let bgSunken = Color(hex: 0xF0EEE6)
    static let bgPanel = Color(hex: 0xF5F4ED)
    static let sidebar = Color(hex: 0xECEAE2)
    static let surface = Color(hex: 0xFFFFFF)
    static let text = Color(hex: 0x141413)
    static let textSecondary = Color(hex: 0x3D3D3A)
    static let textMuted = Color(hex: 0x5E5D59)
    static let border = Color(hex: 0x1F1E1D, opacity: 0.15)
    static let divider = Color(hex: 0x1F1E1D, opacity: 0.08)
    static let live = Color(hex: 0xD97757)
    static let liveText = Color(hex: 0xA8502F)
    static let liveBg = Color(hex: 0xF7E6DC)
    static let liveColumn = Color(hex: 0xF5E8E0)
    static let next = Color(hex: 0x2A6FC4)
    static let done = Color(hex: 0x5E7045)
    static let doneBg = Color(hex: 0xE4E9DA)
    static let ideaBorder = Color(hex: 0x9C9A92)

    // MARK: 폰트

    /// 본문 맨 위 페이지 제목. 세리프 500.
    static let pageTitle = Font.system(size: 26, weight: .medium, design: .serif)
    static let section = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let tableHeader = Font.system(size: 11, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionLarge = Font.system(size: 12)
    static let captionLargeMedium = Font.system(size: 12, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let cardTitle = Font.system(size: 14, weight: .medium)

    // MARK: 모서리

    enum Radius {
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
        static let button: CGFloat = 8
        static let row: CGFloat = 6
    }

    // MARK: 간격

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 7
        static let m: CGFloat = 10
        static let rowH: CGFloat = 12
        static let l: CGFloat = 14
        static let xl: CGFloat = 20
        static let section: CGFloat = 28
        static let pageH: CGFloat = 24
        static let pageV: CGFloat = 28
        /// 서브에이전트 줄·카드 들여쓰기
        static let indent: CGFloat = 14
    }

    // MARK: 크기

    enum Size {
        static let dot: CGFloat = 8
        static let dotStroke: CGFloat = 1.5
        static let ideaDash: [CGFloat] = [2, 1.5]
        static let rowHeight: CGFloat = 34
        static let projectRowHeight: CGFloat = 32
        static let inspectorWidth: CGFloat = 280
        static let sidebarWidth: CGFloat = 230
        static let sidebarMaxWidth: CGFloat = 280
        static let sidebarMinWidth: CGFloat = 200
        static let inspectorMinWidth: CGFloat = 240
        static let inspectorMaxWidth: CGFloat = 340
        static let sidebarKeyWidth: CGFloat = 30
        static let windowWidth: CGFloat = 1280
        static let windowHeight: CGFloat = 820
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 560
    }

    /// 표 열 너비. 제목·이름 열은 남는 폭을 모두 쓰고, 경로 열은 범위 안에서 줄어든다. 좁으면 `TableWidth`가 열을 숨긴다.
    enum Columns {
        static let activeCard: CGFloat = 90
        static let activeFile: ClosedRange<CGFloat> = 120...200
        static let activeTitleMin: CGFloat = 200
        static let activeSession: CGFloat = 110
        static let activeElapsed: CGFloat = 80
        static let projectFolder: ClosedRange<CGFloat> = 120...200
        static let projectNameMin: CGFloat = 160
        static let projectCount: CGFloat = 64
        static let projectCountCompact: CGFloat = 48
        static let projectActivity: CGFloat = 96
    }
}

extension Color {
    /// 0xRRGGBB, sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
