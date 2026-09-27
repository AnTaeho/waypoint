import Foundation
import SwiftData

@Model
public final class Event {
    public var id: UUID = UUID()
    public var project: Project?
    public var card: Card?
    public var session: Session?
    public var at: Date = Date()
    public var typeRaw: String = EventType.note.rawValue
    /// JSON
    public var payload: Data?

    public init(type: EventType, at: Date = Date(), payload: Data? = nil) {
        self.typeRaw = type.rawValue
        self.at = at
        self.payload = payload
    }

    public var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .note }
        set { typeRaw = newValue.rawValue }
    }

    /// payload를 JSON 객체로 읽는다. 없거나 깨졌으면 빈 사전.
    public var payloadObject: [String: Any] {
        guard let payload,
              let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// payload를 Decodable 타입으로 읽는다.
    public func decodePayload<T: Decodable>(_ type: T.Type) -> T? {
        guard let payload else { return nil }
        return try? JSONDecoder().decode(T.self, from: payload)
    }

    /// 이벤트를 만들어 context에 넣고 관계를 잇는다.
    /// project를 안 주면 card → session 순으로 프로젝트를 따라간다.
    @discardableResult
    public static func record(
        _ type: EventType,
        in context: ModelContext,
        project: Project? = nil,
        card: Card? = nil,
        session: Session? = nil,
        at date: Date,
        payload: [String: EventValue] = [:]
    ) -> Event {
        let event = Event(type: type, at: date, payload: payload.isEmpty ? nil : EventValue.encode(payload))
        context.insert(event)
        event.project = project ?? card?.project ?? session?.project
        event.card = card
        event.session = session
        return event
    }
}

/// 이벤트 payload에 넣는 JSON 값.
public enum EventValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }

    static func encode(_ dict: [String: EventValue]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(dict)
    }

    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    public var intValue: Int? { if case .int(let v) = self { v } else { nil } }
}

extension EventValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension Event {
    /// payload를 `[String: EventValue]`로 읽는다.
    public var payloadValues: [String: EventValue] {
        decodePayload([String: EventValue].self) ?? [:]
    }
}
