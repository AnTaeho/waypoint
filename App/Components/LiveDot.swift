import SwiftUI
import WaypointKit

/// 작업중 점: 8pt 채운 원 + 1.8초 주기로 바깥으로 퍼지는 링. 동작 줄이기 설정이면 링 없음.
struct LiveDot: View {
    var size: CGFloat = Theme.Size.dot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 링 한 번 퍼지는 시간(초)
    private static let period: Double = 1.8

    var body: some View {
        // 링은 시각에서 바로 계산한다(레이아웃 애니메이션이 섞여 링 위치가 어긋나지 않게).
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let phase = reduceMotion
                ? 1
                : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            Circle()
                .fill(Theme.live)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(Theme.live)
                        .scaleEffect(1 + 1.5 * phase)
                        .opacity(0.45 * (1 - phase))
                }
        }
        .accessibilityHidden(true)
    }
}

/// 멈춤 점: 속 빈 원, `liveText` 1.5pt 테두리, 펄스 없음.
struct StalledDot: View {
    var size: CGFloat = Theme.Size.dot

    var body: some View {
        Circle()
            .strokeBorder(Theme.liveText, lineWidth: Theme.Size.dotStroke)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 채운 점(완료·다음 등).
struct FilledDot: View {
    let color: Color
    var size: CGFloat = Theme.Size.dot

    var body: some View {
        Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// 아이디어 점: 점선 원.
struct IdeaDot: View {
    var size: CGFloat = Theme.Size.dot

    var body: some View {
        Circle()
            .strokeBorder(Theme.textMuted, style: StrokeStyle(lineWidth: Theme.Size.dotStroke, dash: Theme.Size.ideaDash))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 카드 작업 상태에 맞는 점. none이면 아무것도 없다.
struct WorkStateDot: View {
    let state: CardWorkState

    var body: some View {
        switch state {
        case .live: LiveDot()
        case .stalled: StalledDot()
        case .none: EmptyView()
        }
    }
}
