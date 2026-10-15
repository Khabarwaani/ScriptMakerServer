public actor FailableStreamingAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol {
    public let spec: Specification
    public private(set) var state: OperationState = .ready
    private let session: Session
    private let strategy = FailableOperationStrategy()
    private var task: Task<Void, Never>?

    public init(spec: Specification, session: Session) {
        self.spec = spec
        self.session = session
    }

    public func instructions() throws(AgenticError) -> String {
        try InstructionAssembler(strategy: strategy).assemble(spec: spec)
    }

    public func execute() async -> AsyncStream<Swift.Result<String, AgenticError>> {
        guard state.canStart else { return failed(.busy) }
        guard !Task.isCancelled else { return failed(.cancelled) }
        let (stream, output) = AsyncStream<Swift.Result<String, AgenticError>>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let work = Task { await run(into: output) }
        task = work
        state = .running
        output.onTermination = { reason in
            if case .cancelled = reason { work.cancel() }
        }
        return stream
    }

    private func run(into output: AsyncStream<Swift.Result<String, AgenticError>>.Continuation) async {
        defer {
            task = nil
            output.finish()
        }
        let result: Swift.Result<String, AgenticError>
        do {
            let response = await session.stream(
                to: spec.inputJSON.rawValue, instructions: try instructions(), for: id
            ) { text in
                if case .terminated = output.yield(.success(text)) {
                    throw AgenticError.cancelled
                }
            }
            result = Task.isCancelled ? .failure(.cancelled) : strategy.result(from: response)
        } catch {
            result = .failure(error)
        }
        finish(result)
        output.yield(result)
    }

    private func failed(_ error: AgenticError) -> AsyncStream<Swift.Result<String, AgenticError>> {
        AsyncStream { output in
            output.yield(.failure(error))
            output.finish()
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
