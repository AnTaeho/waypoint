import CoreText
import Foundation

/// 앱 번들의 나눔스퀘어라운드(`App/Fonts`)를 이 프로세스에만 등록한다.
/// 등록에 실패해도 `Font.custom`이 시스템 폰트로 떨어지므로 앱은 계속 뜬다.
enum FontRegistry {
    static func registerBundledFonts() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls where url.lastPathComponent.hasPrefix("NanumSquareRound") {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // 105(이미 등록됨)는 미리보기·재실행에서 생길 수 있어 무시해도 된다.
                let reason = error?.takeRetainedValue().localizedDescription ?? "알 수 없음"
                NSLog("Waypoint 폰트 등록 실패 \(url.lastPathComponent): \(reason)")
            }
        }
    }
}
