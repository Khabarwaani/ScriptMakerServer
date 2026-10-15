import Foundation

extension AgenticSessionProtocol {
    public func stream<Operation: AgenticOperationProtocol>(_ operation: Operation) async -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), Never>
    ) {
        let (snapshots, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let error = AgenticSessionError.unsupportedStreaming
        continuation.finish(throwing: error)
        let result = Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), Never> {
            (content: .failure(error as NSError), metadata: nil)
        }
        return (snapshots: snapshots, result: result)
    }
}
