internal import JSONSchema

enum SchemaValidator {
    static func validate(_ text: String) throws {
        let value: JSONValue
        do {
            value = try JSONValue.parse(text)
        } catch {
            throw JSONValidationError.invalidJSON
        }

        if let dialect = value.object?["$schema"]?.string,
           dialect != "https://json-schema.org/draft/2020-12/schema" {
            throw JSONValidationError.unsupportedDialect
        }

        let result: ValidationResult
        do {
            // Bundled meta-schemas are resolved locally; no network fetch occurs.
            result = try Dialect.draft2020_12.validateSchema(value)
        } catch {
            throw JSONValidationError.validatorUnavailable
        }

        guard result.isEvaluationComplete else {
            throw JSONValidationError.validatorUnavailable
        }
        guard result.isValid else {
            let violations = (result.errors ?? []).flatMap(leafViolations)
            throw JSONValidationError.invalidSchema(violations)
        }
    }

    private static func leafViolations(_ error: ValidationError) -> [SchemaViolation] {
        if let children = error.errors, !children.isEmpty {
            return children.flatMap(leafViolations)
        }
        return [SchemaViolation(
            path: error.instanceLocation.description,
            keyword: error.keyword
        )]
    }
}
