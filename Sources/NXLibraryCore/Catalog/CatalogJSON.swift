import Foundation

/// A JSON value kept exactly as it was read: the catalog holds the records and sources of an integration it does not
/// know this way and writes them back unchanged. Numbers are `Decimal`, never `Double`, so a large integer keeps
/// every digit.
public indirect enum CatalogJSON: Codable, Equatable, Sendable {
    case object([String: CatalogJSON])
    case array([CatalogJSON])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Decimal.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([CatalogJSON].self) { self = .array(value) }
        else { self = .object(try c.decode([String: CatalogJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }

    /// An object's member; nil for a missing key or a value that is not an object.
    public subscript(key: String) -> CatalogJSON? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// `value` as JSON, the way `JSONEncoder` writes it.
    public init(encoding value: some Encodable) throws {
        self = try JSONDecoder().decode(CatalogJSON.self, from: JSONEncoder().encode(value))
    }

    /// The value read back as `type`, the way `JSONDecoder` reads it.
    public func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}
