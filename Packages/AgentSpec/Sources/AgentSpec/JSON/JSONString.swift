import Foundation
internal import JSONSchema

/// Immutable text that has been validated as a complete JSON value.
public struct JSONString: Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Validates JSON syntax, preserving the original text.
    public init(_ value: String) throws {
        do {
            _ = try JSONValue.parse(value)
        } catch {
            throw JSONValidationError.invalidJSON
        }
        rawValue = value
    }

    /// Encodes a model as compact JSON using Foundation's default strategies.
    public init<T: Encodable>(encoding value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try self.init(String(decoding: data, as: UTF8.self))
    }

    /// Invalid hardcoded JSON is a programming error. Use init(_:) for dynamic text.
    public init(stringLiteral value: String) {
        do {
            try self.init(value)
        } catch {
            preconditionFailure("Invalid JSON string literal")
        }
    }
}
