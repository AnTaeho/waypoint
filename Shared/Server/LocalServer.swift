#if os(macOS)
import Foundation
import Network

/// 127.0.0.1 전용 HTTP/1.1 서버(Network.framework). 요청마다 연결 하나, 응답 후 닫는다.
/// 연결 받기·읽기는 서버 전용 큐에서 한다. 먼저 `fastHandler`(서버 큐, 메인 큐를 기다리지 않는다)에 물어
/// 응답이 있으면 바로 보내고, 없으면 요청 처리(`handler`)를 메인 액터에서 부른다. 상태 변경도 메인 액터에서 알린다.
@MainActor
public final class LocalServer {
    /// 평소용 포트. 인스턴스별 포트는 `AppInstance.port()`.
    public static let defaultPort: UInt16 = AppInstance.stable.defaultPort

    public enum State: Equatable, Sendable {
        case stopped
        case starting
        case ready
        /// 포트 사용 중 등으로 열지 못함
        case failed(String)
    }

    public let port: UInt16
    public private(set) var state: State = .stopped {
        didSet { onStateChange?(state) }
    }
    public var onStateChange: ((State) -> Void)?

    public typealias FastHandler = @Sendable (HTTPRequest) -> HTTPResponse?
    private let handler: (HTTPRequest) -> HTTPResponse
    private let fastHandler: FastHandler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.antaeho.waypoint.local-server")

    /// 한 요청을 받는 데 허용하는 시간(초). 넘으면 연결을 끊는다.
    private nonisolated static let receiveTimeout: TimeInterval = 5

    /// - Parameter fastHandler: 서버 큐에서 먼저 부른다. 메인 액터 상태를 건드리지 않는 요청(블록 수신 확인)만 응답하고 나머지는 nil.
    public init(port: UInt16 = LocalServer.defaultPort, fastHandler: @escaping FastHandler = { _ in nil },
                handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = port
        self.fastHandler = fastHandler
        self.handler = handler
    }

    public func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // 루프백에만 묶는다(외부에서 접속 불가).
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        do {
            let listener = try NWListener(using: parameters)
            let queue = queue
            let fast = fastHandler
            let toMain: @Sendable (HTTPRequest, NWConnection) -> Void = { [weak self] request, connection in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { connection.cancel(); return }
                        Self.send(self.handler(request), on: connection)
                    }
                }
            }
            listener.newConnectionHandler = { connection in
                Self.accept(connection, queue: queue, fast: fast, toMain: toMain)
            }
            listener.stateUpdateHandler = { [weak self] newState in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.update(newState) } }
            }
            self.listener = listener
            state = .starting
            listener.start(queue: queue)
        } catch {
            state = .failed(String(describing: error))
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func update(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            state = .ready
        case .failed(let error):
            state = .failed(String(describing: error))
            listener?.cancel()
            listener = nil
        case .cancelled:
            if case .failed = state { return }
            state = .stopped
        default:
            break
        }
    }

    private nonisolated static func accept(_ connection: NWConnection, queue: DispatchQueue, fast: @escaping FastHandler,
                                           toMain: @escaping @Sendable (HTTPRequest, NWConnection) -> Void) {
        connection.start(queue: queue)
        let acceptedAt = Date()
        receive(on: connection, buffer: Data(), acceptedAt: acceptedAt,
                deadline: acceptedAt.addingTimeInterval(receiveTimeout), fast: fast, toMain: toMain)
    }

    private nonisolated static func receive(on connection: NWConnection, buffer: Data, acceptedAt: Date, deadline: Date,
                                            fast: @escaping FastHandler,
                                            toMain: @escaping @Sendable (HTTPRequest, NWConnection) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .request(var request):
                request.receivedAt = acceptedAt
                if let response = fast(request) {
                    send(response, on: connection)
                } else {
                    toMain(request, connection)
                }
            case .invalid:
                send(.badRequest, on: connection)
            case .incomplete:
                if error != nil || isComplete || Date() > deadline {
                    connection.cancel()
                } else {
                    receive(on: connection, buffer: buffer, acceptedAt: acceptedAt, deadline: deadline,
                            fast: fast, toMain: toMain)
                }
            }
        }
    }

    private nonisolated static func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
#endif
