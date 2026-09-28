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
    /// 작업중 카드 그림자(`live` 10%)
    static let liveShadow = Color(hex: 0xD97757, opacity: 0.10)
    /// 사용량 막대 바탕. `divider`(8%)는 사이드바 배경에서 묻혀 조금 진하게.
    static let gaugeTrack = Color(hex: 0x1F1E1D, opacity: 0.12)

    // MARK: 폰트

    /// 나눔스퀘어라운드 굵기(PostScript 이름). 파일은 `App/Fonts`, 등록은 `FontRegistry`.
    /// 등록이 안 되면 `Font.custom`이 시스템 폰트로 그린다.
    enum Face: String {
        case regular = "NanumSquareRoundR"
        case bold = "NanumSquareRoundB"
    }

    /// Dynamic Type을 따르지 않는 고정 크기(기존 `Font.system(size:)`와 같게).
    static func rounded(_ size: CGFloat, _ face: Face = .regular) -> Font {
        Font.custom(face.rawValue, fixedSize: size)
    }

    /// 본문 맨 위 페이지 제목. 나눔스퀘어라운드 B.
    static let pageTitle = rounded(26, .bold)
    static let section = rounded(13, .bold)
    /// 카드 상세 본문의 구역 제목(완료 조건·히스토리)
    static let sectionLarge = rounded(14, .bold)
    /// 인스펙터 구역 제목
    static let inspectorSection = rounded(12, .bold)
    static let body = rounded(13)
    static let bodyMedium = rounded(13, .bold)
    static let bodyStrong = rounded(13, .bold)
    static let tableHeader = rounded(11, .bold)
    static let caption = rounded(11)
    static let captionLarge = rounded(11.5)
    static let captionLargeMedium = rounded(11.5, .bold)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let cardTitle = rounded(14, .bold)
    /// 보드의 카드 없는 세션 타일 제목 자리(마지막 요청 문장·「카드 없음」). 카드 제목과 같은 크기, 보통 굵기.
    static let sessionTileTitle = rounded(14)
    static let monoCaption = Font.system(size: 11, design: .monospaced)
    /// 카드 상세 제목. 나눔스퀘어라운드 B.
    static let detailTitle = rounded(28, .bold)
    static let detailBody = rounded(14)

    // MARK: 모서리

    enum Radius {
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
        static let button: CGFloat = 8
        static let row: CGFloat = 6
        /// 카드 안의 세션 정보 상자
        static let box: CGFloat = 7
        /// 키 배지 같은 작은 테두리
        static let badge: CGFloat = 5
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
        /// 아이디어 카드 점선 테두리
        static let ideaCardDash: [CGFloat] = [5, 3]
        static let rowHeight: CGFloat = 34
        static let projectRowHeight: CGFloat = 32
        static let inspectorWidth: CGFloat = 280
        static let progressHeight: CGFloat = 4
        static let cardBorder: CGFloat = 1
        static let liveBorder: CGFloat = 1.5
        static let liveShadowRadius: CGFloat = 5
        static let liveShadowY: CGFloat = 2
        /// 보드 한 칸의 최소 폭. 1280pt 창에 사이드바·인스펙터가 열려도 네 칸이 다 들어가는 값. 더 좁으면 보드를 가로로 넘긴다.
        static let boardColumnMinWidth: CGFloat = 165
        static let checkbox: CGFloat = 16
        /// 카드 상세 본문 최대 폭
        static let detailBodyMaxWidth: CGFloat = 720
        /// 인스펙터 이름표 열
        static let inspectorLabelWidth: CGFloat = 80
        static let linkedCardIDWidth: CGFloat = 56
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
        /// 사이드바 사용량 막대 높이
        static let gaugeBar: CGFloat = 4
        /// 사용량 게이지 이름표(「5시간」「7일」) 열
        static let gaugeLabelWidth: CGFloat = 34
        /// 사용량 게이지 숫자(「100%」) 열
        static let gaugeValueWidth: CGFloat = 34
    }

    /// 사이드바 사용량 게이지
    enum Usage {
        /// 이 값(%) 이상이면 막대·숫자를 `liveText`로 진하게
        static let highPercent = 80
        /// 기록이 오래됐을 때 게이지 불투명도
        static let staleOpacity: Double = 0.45
    }

    /// 표 열 너비. 제목·이름 열은 남는 폭을 모두 쓰고, 경로 열은 범위 안에서 줄어든다. 좁으면 `TableWidth`가 열을 숨긴다.
    /// 보드
    enum Board {
        /// 불투명도: 완료 카드
        static let doneOpacity: Double = 0.85
        /// 아이디어 칸에 처음 보이는 카드 수
        static let ideaPreviewCount = 3
    }

    /// 지침 문서
    enum Guide {
        /// 제목 1·2·3단계(4단계부터는 3단계와 같게) 크기. 굵기는 B.
        static let h1Size: CGFloat = 22
        static let h2Size: CGFloat = 17
        static let h3Size: CGFloat = 14.5
        static let body = rounded(13.5)
        static let bodySize: CGFloat = 13.5
        static let code = Font.system(size: 12, design: .monospaced)
        /// 편집기·비교 화면 원문
        static let source = Font.system(size: 12.5, design: .monospaced)
        /// 문단·목록 줄 간격
        static let lineSpacing: CGFloat = 3
        /// 인라인 코드는 본문보다 1pt 작게, 표 칸은 0.5pt 작게
        static let inlineCodeShrink: CGFloat = 1
        static let tableTextShrink: CGFloat = 0.5
        /// 충돌 비교 한 줄의 위아래 여백
        static let diffLinePadding: CGFloat = 1
        static let tocWidth: CGFloat = 180
        /// 이 폭보다 좁으면 목차를 숨긴다
        static let tocMinBodyWidth: CGFloat = 620
        static let readMaxWidth: CGFloat = 760
        static let quoteBar: CGFloat = 3
        static let tableCellMinWidth: CGFloat = 60
        /// 문서 이름 칩 줄 높이
        static let tabHeight: CGFloat = 26
        /// 충돌 비교: 로컬에만 있는 줄 / 앱에만 있는 줄 배경
        static let inspectorLabelWidth: CGFloat = 64
        /// 문서 이름 옆 「동기화되지 않음」 점
        static let stateDot: CGFloat = 5
        static let versionSheetWidth: ClosedRange<CGFloat> = 560...640
        static let versionSheetHeight: ClosedRange<CGFloat> = 420...560
        static let removedLine = liveBg
        static let addedLine = doneBg
    }

    /// 새 프로젝트 등록 창
    enum Init {
        static let windowWidth: CGFloat = 760
        static let windowHeight: CGFloat = 640
        static let padding: CGFloat = 30
        /// 구역 사이
        static let gap: CGFloat = 20
        /// 이름표와 입력 칸 사이
        static let labelGap: CGFloat = 6
        static let keyWidth: CGFloat = 110
        static let fieldHeight: CGFloat = 36
        static let fieldPadding: CGFloat = 12
        static let field = rounded(14)
        static let label = rounded(12)
        /// 경로·스택 줄의 이름표 열
        static let rowLabelWidth: CGFloat = 44
        static let chipH: CGFloat = 9
        static let chipV: CGFloat = 3
        static let chipGap: CGFloat = 6
        static let stackInputWidth: CGFloat = 110
        /// 지침 문서·초기 카드 상자
        static let boxPadding: CGFloat = 14
        static let boxRowGap: CGFloat = 9
    }

    /// iPhone 화면(`iPhone.dc.html`, 390pt 폭 기준)
    enum Phone {
        /// 날짜 줄 위의 「작업중 N」 제목
        static let title = rounded(30, .bold)
        static let date = rounded(13)
        static let section = rounded(14, .bold)
        static let cardTitle = rounded(15, .bold)
        static let body = rounded(15)
        static let elapsed = rounded(12, .bold)
        static let stalled = rounded(12)
        static let button = rounded(13, .bold)
        static let meta = Font.system(size: 11, design: .monospaced)
        /// 카드 상세 제목
        static let detailTitle = rounded(22, .bold)
        /// 화면 좌우 여백
        static let gutter: CGFloat = 18
        /// 구역 사이
        static let sectionGap: CGFloat = 18
        /// 카드 사이
        static let cardGap: CGFloat = 10
        /// 카드 안 줄 사이
        static let lineGap: CGFloat = 8
        static let cardPadding: CGFloat = 14
        static let cardRadius: CGFloat = 14
        /// 서브에이전트 카드 들여쓰기
        static let indent: CGFloat = 16
        static let buttonHeight: CGFloat = 36
        static let buttonPaddingH: CGFloat = 14
        static let titleLineSpacing: CGFloat = 4
    }

    /// 개발용 인스턴스(Waypoint Dev) 표시
    enum Dev {
        static let badgeFont = rounded(11, .bold)
        static let badgeText = Theme.next
        static let badgeBg = Color(hex: 0x2A6FC4, opacity: 0.12)
        static let badgePaddingH: CGFloat = 7
        static let badgePaddingV: CGFloat = 2
        /// 메뉴 막대 아이콘(평소용은 `signpost.right`)
        static let menuBarSymbol = "hammer"
    }

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
