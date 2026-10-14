struct SchemaViolation: Sendable, Equatable {
    let path: String
    let keyword: String
}

enum JSONValidationError: Error, Sendable, Equatable {
    case invalidJSON
    case invalidSchema([SchemaViolation])
    case unsupportedDialect
    case validatorUnavailable
}

struct SchemaDerivationError: Error, Sendable, Equatable {
    let typeName: String
    let reason: String
}
