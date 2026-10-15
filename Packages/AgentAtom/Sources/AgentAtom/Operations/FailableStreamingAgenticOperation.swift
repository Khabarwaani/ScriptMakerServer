import Foundation

public struct FailableStreamingAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol {
    public let id: UUID
    public let spec: Specification
    private let runner: OperationRunner<Session>

    public var isExecuting: Bool {
        get async { await runner.isExecuting }
    }

    public init(spec: Specification, session: Session) {
        let id = UUID()
        self.id = id
        self.spec = spec
        self.runner = OperationRunner(operationID: id, session: session)
    }

    public func makeInstructions() throws -> String {
        try OperationInstructionAssembler(strategy: FailableInstructionStrategy()).assemble(spec: spec)
    }

    public func execute() async -> AsyncStream<Result<String, AgenticOperationError>> {
        await runner.stream(
            input: spec.inputJSON.rawValue,
            instructions: Result { try makeInstructions() },
            allowsFailure: true)
    }

    public func cancel() async {
        await runner.cancel()
    }

    public func pause() async throws(AgenticOperationError) {
        try await runner.pause()
    }

    public func resume() async throws(AgenticOperationError) {
        try await runner.resume()
    }
}
