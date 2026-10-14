internal import JSONSchema

extension JSONSchema {
    var isValid: Bool {
        // Draft 2020-12 is the JSON Schema standard version used to validate schema structure.
        guard let value = try? JSONValue.parse(rawValue),
              let result = try? Dialect.draft2020_12.validateSchema(value) else {
            return false
        }
        return result.isEvaluationComplete && result.isValid
    }
}
