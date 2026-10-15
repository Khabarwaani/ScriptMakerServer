import Foundation

extension AgenticSessionProtocol {
    public func stream(_ operation: any AgenticOperationProtocol) async throws -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    ) {
        throw AgenticSessionError.unsupportedStreaming
    }
}
