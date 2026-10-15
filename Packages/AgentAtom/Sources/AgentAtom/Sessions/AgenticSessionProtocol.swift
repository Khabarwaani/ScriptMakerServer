public protocol AgenticSessionProtocol: Sendable {
    func respond(to request: AgenticRequest) async throws -> AgenticResponse<AgenticContent>
    func streamResponse(to request: AgenticRequest) async throws -> AgenticStream<AgenticContent>
}

extension AgenticSessionProtocol {
    public func streamResponse(to request: AgenticRequest) async throws -> AgenticStream<AgenticContent> {
        throw AgenticSessionError.unsupportedStreaming
    }

    public func execute<Operation: AgenticOperationProtocol>(
        _ operation: Operation
    ) async throws -> AgenticResponse<Operation.Output> {
        try checkCancellation()
        let response = try await respond(to: operation.makeRequest())
        try checkCancellation()
        return AgenticResponse(content: try operation.decode(response.content), metadata: response.metadata)
    }

    public func stream<Operation: AgenticOperationProtocol>(
        _ operation: Operation
    ) async throws -> AgenticStream<Operation.Output> {
        try checkCancellation()
        let source = try await streamResponse(to: operation.makeRequest())
        if Task.isCancelled {
            source.cancel()
            throw AgenticSessionError.cancelled
        }
        let completion = Task {
            let response = try await source.result()
            try checkCancellation()
            return AgenticResponse(content: try operation.decode(response.content), metadata: response.metadata)
        }
        return AgenticStream(snapshots: source.snapshots, completion: completion, onCancel: { source.cancel() })
    }
}

/// One consumer for snapshots; only result() establishes completed, typed success.
public final class AgenticStream<Output: Sendable>: Sendable {
    public let snapshots: AsyncThrowingStream<AgenticContent, any Error>
    private let completion: Task<AgenticResponse<Output>, any Error>
    private let onCancel: @Sendable () -> Void

    public init(
        snapshots: AsyncThrowingStream<AgenticContent, any Error>,
        completion: Task<AgenticResponse<Output>, any Error>,
        onCancel: @escaping @Sendable () -> Void = {}
    ) {
        self.snapshots = snapshots
        self.completion = completion
        self.onCancel = onCancel
    }

    public func result() async throws -> AgenticResponse<Output> {
        try await withTaskCancellationHandler {
            try checkCancellation()
            let response = try await completion.value
            try checkCancellation()
            return response
        } onCancel: {
            cancel()
        }
    }

    public func cancel() {
        completion.cancel()
        onCancel()
    }

    deinit {
        completion.cancel()
        onCancel()
    }
}

private func checkCancellation() throws {
    if Task.isCancelled { throw AgenticSessionError.cancelled }
}
