import Foundation

extension AgenticSessionProtocol {
    public func stream<Operation: AgenticOperationProtocol>(_ operation: Operation) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    ) {
        throw AgenticSessionError.unsupportedStreaming
    }
}
