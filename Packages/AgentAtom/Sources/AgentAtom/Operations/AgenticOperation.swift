public actor AgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol {
    public let spec: Specification
    public private(set) var state: OperationState = .ready
    private let session: Session
    private let strategy = JSONOperationStrategy()
    private var task: Task<Swift.Result<String, AgenticError>, Never>?

    public init(spec: Specification, session: Session) {
        self.spec = spec
        self.session = session
    }

    public func instructions() throws(AgenticError) -> String {
        try InstructionAssembler(strategy: strategy).assemble(spec: spec)
    }

    public func execute() async -> Swift.Result<String, AgenticError> {
        guard state.canStart else { return .failure(.busy) }
        guard !Task.isCancelled else { return .failure(.cancelled) }
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
            guard !Task.isCancelled else { return .failure(.cancelled) }
            return strategy.result(from: response)
        } catch {
            return .failure(error)
        }
    }

    private func finish(_ result: Swift.Result<String, AgenticError>) {
        switch result {
        case .success: state = .completed
        case .failure(.cancelled): state = .cancelled
        case .failure: state = .failed
        }
    }

    public func cancel() {
        switch state {
        case .running, .paused:
            state = .cancelling
            task?.cancel()
        case .ready, .cancelling, .completed, .cancelled, .failed:
            break
        }
    }

    public func pause() async throws(AgenticError) {
        guard let work = task else { throw .notRunning }
        guard state == .running else { throw .cannotPause }
        try await session.pause(id)
        guard task == work else { throw .notRunning }
        guard state == .running else { throw .cannotPause }
        state = .paused
    }

    public func resume() async throws(AgenticError) {
        guard let work = task else { throw .notRunning }
        guard state == .paused else { throw .cannotResume }
        try await session.resume(id)
        guard task == work else { throw .notRunning }
        guard state == .paused else { throw .cannotResume }
        state = .running
    }
}
