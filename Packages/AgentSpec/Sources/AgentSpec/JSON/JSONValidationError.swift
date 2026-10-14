/// A schema violation without dependency-specific diagnostics or payload values.
public struct SchemaViolation: Sendable, Equatable {
    public let path: String
    public let keyword: String

    public init(path: String, keyword: String) {
        self.path = path
        self.keyword = keyword
    }
}

/// Recoverable failures from the validated JSON initializers.
public enum JSONValidationError: Error, Sendable, Equatable {
    case invalidJSON
    case invalidSchema([SchemaViolation])
    case unsupportedDialect
    case validatorUnavailable
}

/// Type-driven derivation cannot describe the requested model safely.
public struct SchemaDerivationError: Error, Sendable, Equatable {
    public let typeName: String
    public let reason: String

    public init(typeName: String, reason: String) {
        self.typeName = typeName
        self.reason = reason
    }
}
