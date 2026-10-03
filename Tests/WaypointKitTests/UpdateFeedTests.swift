import Foundation
import Testing
@testable import WaypointKit

/// TRK-56: 피드 주소와 공개 키가 둘 다 있어야 자동 업데이트를 켠다.
@Suite struct UpdateFeedTests {
    let key = "rQ94D4N8zL7HR322vQkicieI0AwuMkKgVIPX40PSgkE="

    @Test func enabledWithFeedAndKey() throws {
        let feed = try #require(UpdateFeed(info: ["SUFeedURL": "https://example.com/waypoint/appcast.xml", "SUPublicEDKey": key]))
        #expect(feed.url.absoluteString == "https://example.com/waypoint/appcast.xml")
        #expect(feed.publicKey == key)
        // 로컬 확인용 http, 앞뒤 공백
        let local = try #require(UpdateFeed(info: ["SUFeedURL": " http://127.0.0.1:8099/appcast.xml\n", "SUPublicEDKey": " \(key) "]))
        #expect(local.url.host == "127.0.0.1")
    }

    @Test func disabledWithoutFeed() {
        // 기본 빌드: 빌드 설정이 비어 Info.plist에 빈 문자열이 들어간다
        #expect(UpdateFeed(info: ["SUFeedURL": "", "SUPublicEDKey": key]) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": "   ", "SUPublicEDKey": key]) == nil)
        #expect(UpdateFeed(info: ["SUPublicEDKey": key]) == nil)
        #expect(UpdateFeed(info: nil) == nil)
        // 치환되지 않은 변수, 다른 스킴, 호스트 없음, 문자열이 아닌 값
        for bad: Any in ["$(WAYPOINT_FEED_URL)", "file:///tmp/appcast.xml", "ftp://example.com/a.xml", "https://", "appcast.xml", 42] {
            #expect(UpdateFeed(info: ["SUFeedURL": bad, "SUPublicEDKey": key]) == nil, "\(bad)")
        }
    }

    @Test func disabledWithoutValidKey() {
        let url = "https://example.com/appcast.xml"
        #expect(UpdateFeed(info: ["SUFeedURL": url]) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": url, "SUPublicEDKey": ""]) == nil)
        #expect(UpdateFeed(info: ["SUFeedURL": url, "SUPublicEDKey": "$(WAYPOINT_UPDATE_PUBLIC_KEY)"]) == nil)
        // base64지만 32바이트가 아님
        #expect(UpdateFeed(info: ["SUFeedURL": url, "SUPublicEDKey": "aGVsbG8="]) == nil)
    }
}
