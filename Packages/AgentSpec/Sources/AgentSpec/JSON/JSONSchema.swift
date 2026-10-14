public struct JSONSchema: Sendable, Equatable {
    public let rawValue: String
}

extension JSONSchema: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { JSONString(rawValue)?.description ?? rawValue }

    public var debugDescription: String { description }
}
