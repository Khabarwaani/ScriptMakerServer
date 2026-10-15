import Foundation

public protocol AgenticOperationProtocol: Sendable {
    var inputJSON: JSONString { get }
    var outputSchema: JSONSchema { get }
    func makeInstructions() throws -> String
    func result(from response: String) throws -> Result<String, NSError>
}
