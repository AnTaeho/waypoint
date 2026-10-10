import Foundation

/// 세션마다 Claude Code가 붙인 이름과 컨텍스트 사용률. 상태줄 중계 스크립트가 저장 폴더에 남기는
/// `session-status.json`(`{"<세션 ID>":{"at":<unix 초>,"name":"…","context":62.5}}`)을 읽는다. 이 Mac에서만 보인다.
public struct SessionStatusSnapshot: Equatable, Sendable {

    public struct Entry: Equatable, Sendable {
        public var name: String?
        /// 0–100
        public var context: Double?
        /// 중계 스크립트가 적은 시각. 없으면 사용률은 보이지 않는다.
        public var at: Date?

        public init(name: String? = nil, context: Double? = nil, at: Date? = nil) {
            self.name = name
            self.context = context
            self.at = at
        }
    }

    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    public static let fileName = "session-status.json"

    /// 이보다 오래된 사용률은 숨긴다(이름은 계속 쓴다). 쉬는 세션의 사용률은 그대로라 넉넉히 둔다.
    public static let contextStaleAfter: TimeInterval = 3 * 60 * 60

    // MARK: 읽기

    /// 읽을 수 없는 내용·항목은 건너뛴다.
    public static func parse(_ data: Data) -> SessionStatusSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .init() }
        var entries: [String: Entry] = [:]
        for (id, value) in root {
            guard !id.isEmpty, let dict = value as? [String: Any] else { continue }
            let entry = Entry(name: name(dict["name"]), context: UsageSnapshot.number(dict["context"]),
                              at: UsageSnapshot.date(dict["at"]))
            if entry.name != nil || entry.context != nil { entries[id] = entry }
        }
        return SessionStatusSnapshot(entries: entries)
    }

    /// 파일이 없거나 읽을 수 없으면 빈 값.
    public static func load(from url: URL) -> SessionStatusSnapshot {
        guard let data = try? Data(contentsOf: url) else { return .init() }
        return parse(data)
    }

    /// 줄바꿈·연속 공백을 공백 하나로 모은 한 줄. 비면 nil.
    static func name(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return line.isEmpty ? nil : line
    }

    // MARK: 화면 값

    /// 세션 ID별 화면 값. 보일 것이 없는 세션은 뺀다.
    public func lines(now: Date) -> [String: SessionStatusLine] {
        entries.compactMapValues { entry in
            let line = SessionStatusLine(name: entry.name, contextPercent: Self.contextPercent(entry, now: now))
            return line == .none ? nil : line
        }
    }

    /// 보일 사용률(0–100 정수). 값이 없거나 오래됐으면 nil.
    static func contextPercent(_ entry: Entry, now: Date) -> Int? {
        guard let context = entry.context, let at = entry.at,
              now.timeIntervalSince(at) <= contextStaleAfter else { return nil }
        return Int(min(max(context, 0), 100).rounded())
    }
}

/// 세션 줄 하나에 얹는 값: 이름과 컨텍스트 사용률.
public struct SessionStatusLine: Equatable, Sendable {
    public var name: String?
    public var contextPercent: Int?

    public init(name: String? = nil, contextPercent: Int? = nil) {
        self.name = name
        self.contextPercent = contextPercent
    }

    public static let none = SessionStatusLine()

    /// 이 값(%) 이상이면 곧 대화가 압축된다. 진하게 보인다.
    public static let highContextPercent = 80

    /// 세션 표시 자리의 글: 이름이 있으면 이름, 없으면 `fallback`(「sess·7f2a」).
    public func label(fallback: String) -> String { name ?? fallback }

    /// 「컨텍스트 62%」. 값이 없으면 nil.
    public var contextText: String? {
        contextPercent.map { "컨텍스트 \($0)%" }
    }

    public var isContextHigh: Bool {
        (contextPercent ?? 0) >= Self.highContextPercent
    }
}
