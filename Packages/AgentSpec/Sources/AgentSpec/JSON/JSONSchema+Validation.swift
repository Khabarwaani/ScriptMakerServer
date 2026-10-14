internal import JSONSchema

extension JSONSchema {
    static func isValid(_ text: String) -> Bool {
        guard let value = try? JSONValue.parse(text),
              let result = try? Dialect.draft2020_12.validateSchema(value) else {
            return false
        }
        return result.isEvaluationComplete && result.isValid
    }
}
