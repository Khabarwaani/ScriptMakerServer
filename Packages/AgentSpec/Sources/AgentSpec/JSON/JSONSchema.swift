public struct JSONSchema: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rawValue: String

    public init?<T: Decodable>(_ type: T.Type) {
        guard let value = try? Self.derive(type), Self.isValid(value) else { return nil }
        rawValue = value
    }

    public var description: String { JSONString(rawValue)?.description ?? rawValue }

    public var debugDescription: String { description }
}
