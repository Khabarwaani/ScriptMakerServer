import Foundation

/// Immutable schema text validated against the Draft 2020-12 meta-schema.
///
/// Standard validity does not imply support by any particular AI provider,
/// and does not verify that a response satisfies the schema.
public struct JSONSchema: Sendable, Equatable {
    public let rawValue: String

    /// Validates schema syntax and its Draft 2020-12 structure.
    /// When $schema is absent, Draft 2020-12 is assumed.
    public init(_ value: String) throws {
        try SchemaValidator.validate(value)
        rawValue = value
    }

    /// Derives and validates the structure of a supported Decodable model.
    ///
    /// Supports ordinary synthesized models. Arbitrary custom decoding cannot
    /// be inferred exactly; supply an explicit schema for those models.
    public init<T: Decodable>(_ type: T.Type) throws {
        try self.init(SchemaDeriver.derive(type))
    }
}
