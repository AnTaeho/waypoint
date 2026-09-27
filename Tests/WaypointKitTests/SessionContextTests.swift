import Foundation
import SwiftData
import Testing
@testable import WaypointKit

@Suite struct SessionContextTests {
    @Test func listsNextOthersAndNotes() throws {
        let h = try HookHarness()
        let p = h.project
        for i in 1...6 { p.makeCard(in: h.context, title: "다음 \(i)", status: .next, at: t0) }
        let busy = p.makeCard(in: h.context, title: "다른 작업", status: .next, at: t0)
        busy.nextSessionNote = "승인금액 케이스 남음"
        let other = makeSession(h.context, p, id: "0ther-session", startedAt: t0, lastSeenAt: t0)
        CardLifecycle.attach(busy, other, at: t0, in: h.context)

        let text = try #require(try h.send("doc-SessionStart", at: t0 + 60))
        #expect(text.contains("다음 할 일:"))
        #expect(text.contains("- LDG-1 다음 1"))
        #expect(text.contains("- LDG-5 다음 5"))
        #expect(!text.contains("LDG-6 다음 6"))
        #expect(text.contains("- LDG-7 다른 작업 (sess·0the)"))
        #expect(text.contains("- LDG-7: 승인금액 케이스 남음"))
    }
}
