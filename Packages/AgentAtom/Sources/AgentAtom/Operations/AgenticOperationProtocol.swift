public protocol AgenticOperationProtocol: Sendable {
    var inputJSON: JSONString { get }
    var outputSchema: JSONSchema { get throws }
    func makeInstructions() throws -> String
    func result(from response: String) throws -> AgenticResult
}
