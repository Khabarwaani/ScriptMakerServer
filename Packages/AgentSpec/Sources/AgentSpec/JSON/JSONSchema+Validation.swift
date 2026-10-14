internal import JSONSchema

extension JSONSchema {
    var isValid: Bool {
        guard let value = try? JSONValue.parse(rawValue),
              let result = try? Dialect.draft2020_12.validateSchema(value) else {
            return false
        }
        return result.isEvaluationComplete && result.isValid
    }
}
