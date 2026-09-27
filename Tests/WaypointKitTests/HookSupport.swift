import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// `Tests/Fixtures/hooks/<name>.json` 원문.
func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/hooks"),
        "픽스처 없음: \(name)"
    )
    return try Data(contentsOf: url)
}

func fixtureInput(_ name: String) throws -> HookInput {
    try #require(HookInput(event: nil, json: try fixture(name)))
}

/// 픽스처의 홈 폴더(`/Users/me`)와 LDG 프로젝트(`~/dev/ledger`)를 갖춘 처리기.
struct HookHarness {
    let container: ModelContainer
    let context: ModelContext
    let processor: HookProcessor
    let project: Project

    /// 픽스처 세션 ID
    static let sessionID = "7f2a9c41-3e8b-4d06-b5a2-9c7e1f4d8b60"
    static let agentID = "a4d2c8f1e0b3a297"

    init() throws {
        let (container, context) = try makeContext()
        self.container = container
        self.context = context
        let project = Project(key: "LDG", name: "가계부 앱", rootPath: "~/dev/ledger", createdAt: t0)
        context.insert(project)
        try context.save()
        self.project = project
        self.processor = HookProcessor(context: context, home: "/Users/me", gitBranch: { _ in "feat/ocr-mapping" })
    }

    @discardableResult
    func send(_ name: String, event: String? = nil, at date: Date) throws -> String? {
        processor.handle(event: event, json: try fixture(name), at: date)
    }

    func session(_ id: String = HookHarness.sessionID) throws -> Session? {
        try context.fetch(FetchDescriptor<Session>(predicate: #Predicate<Session> { $0.id == id })).first
    }

    func card(_ number: Int) -> Card? {
        project.cards?.first { $0.number == number }
    }
}
