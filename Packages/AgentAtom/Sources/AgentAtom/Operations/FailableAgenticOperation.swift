import Foundation

public actor FailableAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol {
    public nonisolated let id: UUID
    public nonisolated let spec: Specification
    private let session: Session
    private let strategy = FailableOperationStrategy()
    private var task: Task<Result<String, AgenticError>, Never>?

    public var isExecuting: Bool { task != nil }

    public init(spec: Specification, session: Session) {
        self.id = UUID()
        self.spec = spec
        self.session = session
    }

    public nonisolated func makeInstructions() throws -> String {
        try OperationInstructionAssembler(strategy: strategy).assemble(spec: spec)
    }

    public func execute() async -> Result<String, AgenticError> {
        guard task == nil else { return .failure(.busy) }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let instructions: String
        do {
            instructions = try makeInstructions()
        } catch {
            return .failure((error as? AgenticError) ?? .invalidInstructions)
        }
        let worker = Task<Result<String, AgenticError>, Never> {
            let response = await session.generate(
                input: spec.inputJSON.rawValue, instructions: instructions, operationID: id)
            if Task.isCancelled { return .failure(.cancelled) }
            return strategy.result(from: response)
        }
        task = worker
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        task = nil
        return result
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
