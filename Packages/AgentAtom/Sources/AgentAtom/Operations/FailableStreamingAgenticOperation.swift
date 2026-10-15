import Foundation

public actor FailableStreamingAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol {
    public nonisolated let id: UUID
    public nonisolated let spec: Specification
    private let session: Session
    private let strategy = FailableOperationStrategy()
    private var task: Task<Void, Never>?

    public var isExecuting: Bool { task != nil }

    public init(spec: Specification, session: Session) {
        self.id = UUID()
        self.spec = spec
        self.session = session
    }

    public nonisolated func makeInstructions() throws -> String {
        try OperationInstructionAssembler(strategy: strategy).assemble(spec: spec)
    }

    public func execute() async -> AsyncStream<Result<String, AgenticError>> {
        let (results, continuation) = AsyncStream<Result<String, AgenticError>>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        if task != nil || Task.isCancelled {
            continuation.yield(.failure(task != nil ? .busy : .cancelled))
            continuation.finish()
            return results
        }
        let instructions: String
        do {
            instructions = try makeInstructions()
        } catch {
            continuation.yield(.failure((error as? AgenticError) ?? .invalidInstructions))
            continuation.finish()
            return results
        }
        let worker = Task {
            defer {
                task = nil
                continuation.finish()
            }
            let response = await session.stream(
                input: spec.inputJSON.rawValue, instructions: instructions, operationID: id
            ) { snapshot in
                if case .terminated = continuation.yield(.success(snapshot)) {
                    throw AgenticError.cancelled
                }
            }
            let result: Result<String, AgenticError> = Task.isCancelled
                ? .failure(.cancelled) : strategy.result(from: response)
            continuation.yield(result)
        }
        task = worker
        continuation.onTermination = { termination in
            if case .cancelled = termination { worker.cancel() }
        }
        return results
    }

    public func cancel() {
        task?.cancel()
    }

    public func pause() async throws(AgenticError) {
        guard task != nil else { throw .notRunning }
        try await session.pause(operationID: id)
    }

    public func resume() async throws(AgenticError) {
        guard task != nil else { throw .notRunning }
        try await session.resume(operationID: id)
    }
}
