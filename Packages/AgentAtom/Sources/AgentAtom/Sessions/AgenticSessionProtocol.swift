import Foundation

public protocol AgenticSessionProtocol: Sendable {
    associatedtype SessionConfiguration: Sendable
    var configuration: SessionConfiguration { get }

    func execute<Operation: AgenticOperationProtocol>(_ operation: Operation) async throws -> (
        content: Result<String, NSError>, metadata: AgenticExecutionMetadata?
    )
    func stream<Operation: AgenticOperationProtocol>(_ operation: Operation) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    )
}
