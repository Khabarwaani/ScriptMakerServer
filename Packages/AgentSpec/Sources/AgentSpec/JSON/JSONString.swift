import Foundation

/// Immutable text that has been validated as a complete JSON value.
public struct JSONString: Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Validates JSON syntax, preserving the original text.
    public init?(_ value: String) {
        guard (try? JSONSerialization.jsonObject(
            with: Data(value.utf8),
            options: [.fragmentsAllowed]
        )) != nil else { return nil }
        rawValue = value
    }

    /// Invalid hardcoded JSON is a programming error. Use init(_:) for dynamic text.
    public init(stringLiteral value: String) {
        guard let json = Self(value) else {
            preconditionFailure("Invalid JSON string literal")
        }
        self = json
    }
}
