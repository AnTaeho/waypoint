import SwiftUI
import WaypointKit

/// 설정 창 「기록」 탭(TRK-47): 남기는 것 · 어디에 · 백업 · 내보내기·지우기. 문장은 `RecordScope`에서 만든다.
struct RecordsTab: View {
    /// 샘플 모드에서는 nil(백업·지우기 없이 범위만 보인다)
    @Environment(AppServices.self) private var services: AppServices?

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                RecordsScopeSections(iCloud: AppInstance.current.cloudKitContainer() != nil)
                if let records = services?.records {
                    RecordsBackupSection(model: records)
                    RecordsDataSection(model: records)
                        .id(Self.bottomID)
                }
            }
            .formStyle(.grouped)
            .onAppear { Self.debugScroll(proxy) }
        }
        .frame(width: Theme.Records.width, height: Theme.Records.height)
    }

    static let bottomID = "records.bottom"

    /// Debug: `-WaypointSettingsScroll bottom`이면 아래 구역(백업·내보내기·지우기)까지 내려 둔다(손 없이 창을 찍을 때).
    private static func debugScroll(_ proxy: ScrollViewProxy) {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "WaypointSettingsScroll") == "bottom" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(bottomID, anchor: .bottom) }
        #endif
    }
}

/// 「남기는 것」「어디에」. 항목마다 한 줄: 이름 · 무엇을 · 보관 기간.
struct RecordsScopeSections: View {
    let iCloud: Bool

    var body: some View {
        Section("남기는 것") {
            ForEach(RecordScope.Item.allCases, id: \.self) { item in
                RecordsLine(title: item.title, detail: item.detail) {
                    Text(item.retention.label)
                }
            }
            Text(RecordScope.notKeptLine)
                .font(Theme.Records.detailFont)
                .foregroundStyle(Theme.Records.detail)
        }
        Section("어디에") {
            let store = RecordScope.storePlace(iCloud: iCloud)
            RecordsLine(title: store.title, detail: store.detail) { EmptyView() }
            RecordsLine(title: RecordScope.localPlaceTitle,
                        detail: RecordScope.localItems.map(\.title).joined(separator: " · ")) { EmptyView() }
        }
    }
}

/// 한 줄: 이름(고정 열) · 흐린 설명 · 오른쪽 값
struct RecordsLine<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            Text(title)
                .frame(minWidth: Theme.Records.labelWidth, alignment: .leading)
            Text(detail)
                .font(Theme.Records.detailFont)
                .foregroundStyle(Theme.Records.detail)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}
