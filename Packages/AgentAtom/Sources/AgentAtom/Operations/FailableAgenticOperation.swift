public actor FailableAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol, OperationLifecycle {
    public let spec: Specification
    public internal(set) var state: OperationState = .ready
    let session: Session
    let strategy = FailableOperationStrategy()
    var task: Task<Swift.Result<String, AgenticError>, Never>?

    public init(spec: Specification, session: Session) {
        self.spec = spec
        self.session = session
    }

    public func execute() async -> Swift.Result<String, AgenticError> {
        guard state.canStart else { return .failure(.busy) }
        let work = Task { await run() }
        task = work
        state = .running
        defer { task = nil }
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        finish(result)
        return result
    }

    private func run() async -> Swift.Result<String, AgenticError> {
        do {
            let response = await session.respond(
                to: spec.inputJSON.rawValue, instructions: try instructions(), for: id)
            return strategy.result(from: response)
        } catch {
            return .failure(error)
        }
    }
}
