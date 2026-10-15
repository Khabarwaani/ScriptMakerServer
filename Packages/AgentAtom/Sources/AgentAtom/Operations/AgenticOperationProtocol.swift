import Foundation

public protocol AgenticOperationProtocol: Sendable {
    associatedtype Specification: Spec
    associatedtype ExecutionResult: Sendable

    var id: UUID { get }
    var spec: Specification { get }
    var isExecuting: Bool { get async }

    func makeInstructions() throws -> String
    func execute() async -> ExecutionResult
    func cancel() async
    func pause() async throws(AgenticError)
    func resume() async throws(AgenticError)
}
