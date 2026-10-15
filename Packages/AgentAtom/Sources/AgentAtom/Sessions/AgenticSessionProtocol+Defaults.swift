import Foundation

extension AgenticSessionProtocol where SessionError == AgenticSessionError {
    public func stream(_ operation: any AgenticOperationProtocol) async throws(AgenticSessionError) -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    ) {
        throw .unsupportedStreaming
    }
}
