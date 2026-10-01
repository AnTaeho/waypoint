#if os(macOS)
import Foundation
import Testing
@testable import WaypointKit

/// 서버 큐의 빠른 경로(블록 수신 확인, TRK-35)는 메인 액터가 바빠도 바로 답한다.
@Suite(.serialized) struct LocalServerTests {
    static func post(_ port: UInt16, _ path: String) async throws -> (status: Int, body: String, seconds: TimeInterval, finished: Date) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 5
        let start = Date()
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self),
                Date().timeIntervalSince(start), Date())
    }

    /// 동기 함수로 메인 액터를 막는다(비동기 문맥에서는 `Thread.sleep`을 바로 부를 수 없다).
    @MainActor static func blockMainActor(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor @Test func fastHandlerAnswersWhileMainActorIsBusy() async throws {
        let port = UInt16.random(in: 49200...49900)
        let server = LocalServer(port: port, fastHandler: { $0.path == "/fast" ? .noContent : nil }) { _ in .text("main") }
        server.start()
        defer { server.stop() }
        for _ in 0..<100 where server.state != .ready { try await Task.sleep(for: .milliseconds(20)) }
        try #require(server.state == .ready)

        let fast = Task.detached { try await Self.post(port, "/fast") }
        Self.blockMainActor(seconds: 1)
        let unblocked = Date()
        let result = try await fast.value
        // 메인 액터가 막혀 있는 동안 끝났다
        #expect(result.finished < unblocked)
        #expect(result.status == 204)
        #expect(result.seconds < 0.5, "빠른 경로가 메인을 기다렸다: \(result.seconds)초")

        // 나머지 요청은 메인 액터의 처리기로 간다
        let main = try await Self.post(port, "/hooks/Stop")
        #expect(main.status == 200 && main.body == "main")
    }
}
#endif
