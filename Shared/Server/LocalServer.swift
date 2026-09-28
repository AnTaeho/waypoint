#if os(macOS)
import Foundation
import Network

/// 127.0.0.1 전용 HTTP/1.1 서버(Network.framework). 요청마다 연결 하나, 응답 후 닫는다.
/// 모든 콜백은 메인 큐에서 돌고, 요청 처리(`handler`)도 메인 액터에서 부른다.
@MainActor
public final class LocalServer {
    public static let defaultPort: UInt16 = 47821

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

    private let handler: (HTTPRequest) -> HTTPResponse
    private var listener: NWListener?

    /// 한 요청을 받는 데 허용하는 시간(초). 넘으면 연결을 끊는다.
    private static let receiveTimeout: TimeInterval = 5

    public init(port: UInt16 = LocalServer.defaultPort, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = port
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
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] newState in
                MainActor.assumeIsolated { self?.update(newState) }
            }
            self.listener = listener
            state = .starting
            listener.start(queue: .main)
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

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        let deadline = Date().addingTimeInterval(Self.receiveTimeout)
        receive(on: connection, buffer: Data(), deadline: deadline)
    }

    private func receive(on connection: NWConnection, buffer: Data, deadline: Date) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequestParser.parse(buffer) {
                case .request(let request):
                    self.send(self.handler(request), on: connection)
                case .invalid:
                    self.send(.badRequest, on: connection)
                case .incomplete:
                    if error != nil || isComplete || Date() > deadline {
                        connection.cancel()
                    } else {
                        self.receive(on: connection, buffer: buffer, deadline: deadline)
                    }
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
#endif
