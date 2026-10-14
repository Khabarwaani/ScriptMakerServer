public struct JSONSchema: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rawValue: String

    public init?<T: Decodable>(_ type: T.Type) {
        guard let value = try? SchemaDerivation().derive(type) else { return nil }
        rawValue = value
        guard isValid else { return nil }
    }

    public var description: String { JSONString(rawValue)?.description ?? rawValue }

    public var debugDescription: String { description }
}
