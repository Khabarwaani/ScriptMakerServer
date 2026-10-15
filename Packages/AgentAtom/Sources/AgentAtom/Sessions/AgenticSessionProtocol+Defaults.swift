import Foundation

extension AgenticSessionProtocol {
    public func stream<Operation: AgenticOperationProtocol>(
        _ operation: Operation
    ) async -> AsyncStream<Result<String, NSError>> {
        AsyncStream { continuation in
            continuation.yield(.failure(AgenticSessionError.unsupportedStreaming as NSError))
            continuation.finish()
        }
    }
}
