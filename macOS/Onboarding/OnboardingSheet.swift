import SwiftUI
import WaypointKit

extension View {
    /// 연결 설정(온보딩) 시트. 메인 창이 여럿이면 먼저 뜬 창 하나에만 띄운다.
    func onboardingSheet(_ services: AppServices?) -> some View {
        modifier(OnboardingSheet(services: services))
    }
}

private struct OnboardingSheet: ViewModifier {
    let services: AppServices?
    /// 창마다 다른 값
    @State private var windowID = UUID()

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: shown) {
                if let services { OnboardingView(services: services, model: services.onboarding) }
            }
            .onAppear { services?.onboarding.claimHost(windowID) }
            .onDisappear { services?.onboarding.releaseHost(windowID) }
    }

    private var shown: Binding<Bool> {
        Binding { services?.onboarding.shows(in: windowID) ?? false } set: { shown in
            // 시트 밖에서 닫혀도(Esc 등) 닫기로 센다
            if !shown { services?.onboarding.close() }
        }
    }
}
