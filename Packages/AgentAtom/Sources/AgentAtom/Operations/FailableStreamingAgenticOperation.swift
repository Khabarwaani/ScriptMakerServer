public actor FailableStreamingAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol, OperationLifecycle {
    public let spec: Specification
    public internal(set) var state: OperationState = .ready
    let session: Session
    let strategy = FailableOperationStrategy()
    var task: Task<Void, Never>?

    public init(spec: Specification, session: Session) {
        self.spec = spec
        self.session = session
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
        defer { output.finish() }
        let result: Swift.Result<String, AgenticError>
        do {
            let response = await session.stream(
                to: spec.inputJSON.rawValue, instructions: try instructions(), for: id
            ) { text in
                if case .terminated = output.yield(.success(text)) {
                    throw AgenticError.cancelled
                }
            }
            result = strategy.result(from: response)
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
}
