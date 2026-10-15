public final class AgenticStream: Sendable {
    public let snapshots: AsyncThrowingStream<String, any Error>
    private let completion: Task<AgenticResponse, any Error>

    public init(
        snapshots: AsyncThrowingStream<String, any Error>,
        completion: Task<AgenticResponse, any Error>
    ) {
        self.snapshots = snapshots
        self.completion = completion
    }

    public func result() async throws -> AgenticResponse {
        try await withTaskCancellationHandler {
            if Task.isCancelled { throw AgenticSessionError.cancelled }
            let response = try await completion.value
            if Task.isCancelled { throw AgenticSessionError.cancelled }
            return response
        } onCancel: {
            completion.cancel()
        }
    }

    public func cancel() { completion.cancel() }

    deinit { completion.cancel() }
}
