import Foundation

public protocol AgenticSessionProtocol: Sendable {
    associatedtype SessionConfiguration: Sendable
    var configuration: SessionConfiguration { get }

    func execute<Operation: AgenticOperationProtocol>(_ operation: Operation) async -> (
        content: Result<String, NSError>, metadata: AgenticExecutionMetadata?
    )
    func stream<Operation: AgenticOperationProtocol>(_ operation: Operation) async -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), Never>
    )
}
