import Testing
@testable import WaypointKit

@Test func versionIsSet() {
    #expect(!WaypointKit.version.isEmpty)
}
