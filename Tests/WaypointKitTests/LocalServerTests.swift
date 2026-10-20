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

    /// 운영체제가 바깥 연결에 쓰는 포트 범위(49152~) 밖에서 열고, 이미 쓰는 포트면 다른 포트로 다시 연다.
    @MainActor static func startOnFreePort(_ make: (UInt16) -> LocalServer) async throws -> LocalServer {
        for _ in 0..<5 {
            let server = make(UInt16.random(in: 38000...38999))
            server.start()
            for _ in 0..<100 where server.state == .starting { try await Task.sleep(for: .milliseconds(20)) }
            if server.state == .ready { return server }
            server.stop()
        }
        throw NoFreePort()
    }

    struct NoFreePort: Error {}

    /// 동기 함수로 메인 액터를 막는다(비동기 문맥에서는 `Thread.sleep`을 바로 부를 수 없다).
    @MainActor static func blockMainActor(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// 연결만 열고 아무것도 보내지 않는 클라이언트. 서버가 닫으면 true, `wait`초 안에 안 닫으면 false.
    static func idleConnectionCloses(_ port: UInt16, wait: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return false }
        var timeout = timeval(tv_sec: wait, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        // 0: 서버가 닫음, -1(EAGAIN): 제한 시간까지 열려 있음
        let read = recv(fd, &byte, 1, 0)
        return read == 0 || (read < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
    }

    // 연결만 열고 보내지 않는 클라이언트도 수신 제한 시간에 끊는다.
    @MainActor @Test func idleConnectionIsClosedAtReceiveTimeout() async throws {
        let server = try await Self.startOnFreePort {
            LocalServer(port: $0, receiveTimeout: 0.3) { _ in .text("main") }
        }
        defer { server.stop() }
        let port = server.port
        let closed = await Task.detached { Self.idleConnectionCloses(port, wait: 3) }.value
        #expect(closed)
        // 제때 온 요청은 그대로 처리한다
        let main = try await Self.post(port, "/hooks/Stop")
        #expect(main.status == 200 && main.body == "main")
    }

    @MainActor @Test func fastHandlerAnswersWhileMainActorIsBusy() async throws {
        let server = try await Self.startOnFreePort {
            LocalServer(port: $0, fastHandler: { $0.path == "/fast" ? .noContent : nil }) { _ in .text("main") }
        }
        defer { server.stop() }
        let port = server.port

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
