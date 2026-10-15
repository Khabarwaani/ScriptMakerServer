protocol OperationStrategy: Sendable {
    var allowsFailure: Bool { get }
    func assemble(role: String, instructions: String, schema: JSONSchema) throws -> String
    func result(from response: Result<String, AgenticError>) -> Result<String, AgenticError>
}
