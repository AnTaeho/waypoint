import Foundation

/// 받은 HTTP/1.1 요청(훅용 최소 구현).
public struct HTTPRequest: Sendable, Equatable {
    public let method: String
    /// 쿼리 문자열을 뺀 경로
    public let path: String
    /// 머리 이름은 소문자
    public let headers: [String: String]
    public let body: Data
}

public enum HTTPParseResult: Sendable, Equatable {
    /// 더 받아야 한다
    case incomplete
    case request(HTTPRequest)
    case invalid
}

public enum HTTPRequestParser {
    /// 본문 최대 크기(1 MiB). 넘으면 invalid.
    public static let maxBodySize = 1 << 20
    /// 머리 최대 크기(16 KiB)
    public static let maxHeaderSize = 16 << 10

    private static let separator = Data("\r\n\r\n".utf8)

    /// 지금까지 받은 바이트로 요청 하나를 읽는다. `Content-Length`가 없으면 본문 없음으로 본다.
    public static func parse(_ data: Data) -> HTTPParseResult {
        guard let end = data.range(of: separator) else {
            return data.count > maxHeaderSize ? .invalid : .incomplete
        }
        guard end.lowerBound <= maxHeaderSize,
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8)
        else { return .invalid }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length: Int
        if let raw = headers["content-length"] {
            guard let n = Int(raw), n >= 0, n <= maxBodySize else { return .invalid }
            length = n
        } else {
            length = 0
        }
        let bodyStart = end.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }
        let body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])

        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        return .request(HTTPRequest(method: String(requestLine[0]), path: path, headers: headers, body: body))
    }
}

/// 보낼 HTTP 응답. 연결은 매번 닫는다(`Connection: close`).
public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let contentType: String?
    public let body: Data

    public init(status: Int, contentType: String? = nil, body: Data = Data()) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    public static func text(_ string: String) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8", body: Data(string.utf8))
    }

    public static let noContent = HTTPResponse(status: 204)
    public static let badRequest = HTTPResponse(status: 400)
    public static let notFound = HTTPResponse(status: 404)
    public static let methodNotAllowed = HTTPResponse(status: 405)

    public var reason: String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if let contentType { head += "Content-Type: \(contentType)\r\n" }
        // 204에는 본문·길이를 싣지 않는다.
        if status != 204 { head += "Content-Length: \(body.count)\r\n" }
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        if status != 204 { data.append(body) }
        return data
    }
}
