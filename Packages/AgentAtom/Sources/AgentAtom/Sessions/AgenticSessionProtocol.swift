import Foundation

public protocol AgenticSessionProtocol: Sendable {
    func execute(_ operation: any AgenticOperationProtocol) async throws -> (
        content: Result<String, NSError>, metadata: AgenticExecutionMetadata?
    )
    func stream(_ operation: any AgenticOperationProtocol) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    )
}
