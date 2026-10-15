public protocol AgenticOperationProtocol: Sendable {
    var inputJSON: JSONString { get }
    var outputSchema: JSONSchema { get throws }
    var instructions: String { get throws }
    func result(from response: String) throws -> AgenticResult
}
