import Foundation

public struct JSONString: Sendable, Equatable {
    public let rawValue: String

    public init?(_ value: String) {
        guard (try? JSONSerialization.jsonObject(
            with: Data(value.utf8),
            options: [.fragmentsAllowed]
        )) != nil else { return nil }
        rawValue = value
    }
}

extension JSONString: ExpressibleByStringLiteral, CustomStringConvertible, CustomDebugStringConvertible {
    /// Invalid literals terminate execution.
    public init(stringLiteral value: String) {
        guard let json = Self(value) else {
            preconditionFailure("Invalid JSON string literal")
        }
        self = json
    }

    public var description: String {
        guard let object = try? JSONSerialization.jsonObject(
            with: Data(rawValue.utf8), options: [.fragmentsAllowed]
        ),
        let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        ),
        let text = String(data: data, encoding: .utf8) else { return rawValue }
        return text
    }

    public var debugDescription: String { description }
}
