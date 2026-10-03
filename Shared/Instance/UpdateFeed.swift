import Foundation

/// 자동 업데이트 설정(TRK-56). 빌드 때 Info.plist에 들어간 피드 주소(`SUFeedURL`, build setting `WAYPOINT_FEED_URL`)와
/// 서명 공개 키(`SUPublicEDKey`, `WAYPOINT_UPDATE_PUBLIC_KEY`)를 읽는다.
/// 둘 다 쓸 수 있을 때만 값이 생기고, nil이면 앱은 업데이트 기능을 열지 않는다(메뉴·설정 항목도 숨김).
/// 피드 주소 기본값은 비어 있다: 평소용(`install-local.sh`)·Dev·피드 없이 만든 배포 빌드는 모두 꺼진다.
public struct UpdateFeed: Sendable, Equatable {
    public static let feedURLInfoKey = "SUFeedURL"
    public static let publicKeyInfoKey = "SUPublicEDKey"

    public let url: URL
    public let publicKey: String

    /// - 피드 주소: 앞뒤 공백을 뗀 뒤 `http`·`https`이고 호스트가 있어야 한다. 비었거나 치환되지 않은 `$(…)`는 꺼짐.
    /// - 공개 키: base64로 풀어 32바이트(Ed25519 공개 키)여야 한다.
    public init?(info: [String: Any]?) {
        guard let rawURL = (info?[Self.feedURLInfoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty
        else { return nil }
        guard let key = (info?[Self.publicKeyInfoKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let decoded = Data(base64Encoded: key), decoded.count == 32
        else { return nil }
        self.url = url
        self.publicKey = key
    }
}
