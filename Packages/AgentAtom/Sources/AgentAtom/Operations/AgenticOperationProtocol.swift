/// A reusable operation with actor-isolated execution and lifecycle control.
public protocol AgenticOperationProtocol: Actor, Identifiable where ID == ObjectIdentifier {
    associatedtype Specification: Spec
    associatedtype Result: Sendable

    var spec: Specification { get }
    var state: OperationState { get }

    /// The final instructions assembled from the specification.
    func instructions() throws(AgenticError) -> String
    /// Starts a run and returns its result or stream; the caller owns no task handle.
    func execute() async -> Result
    /// Cancels the active run, retaining its resources until cleanup completes.
    func cancel()
    /// Pauses the active run if supported by the session.
    func pause() async throws(AgenticError)
    /// Resumes the paused run if supported by the session.
    func resume() async throws(AgenticError)
}

// Defaults share behavior; each actor owns its task and state.
protocol OperationLifecycle: AgenticOperationProtocol {
    associatedtype Session: AgenticSessionProtocol
    associatedtype Strategy: OperationStrategy
    associatedtype Success: Sendable

    var session: Session { get }
    var strategy: Strategy { get }
    var task: Task<Success, Never>? { get set }
    var state: OperationState { get set }
}

extension OperationLifecycle {
    public func instructions() throws(AgenticError) -> String {
        try strategy.assemble(
            role: Specification.role, instructions: spec.instructions,
            schema: Specification.outputSchema)
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
        guard state == .running else { throw .unsupported }
        try await session.pause(id)
        guard task == work else { throw .notRunning }
        guard state == .running else { throw .unsupported }
        state = .paused
    }

    public func resume() async throws(AgenticError) {
        guard let work = task else { throw .notRunning }
        guard state == .paused else { throw .unsupported }
        try await session.resume(id)
        guard task == work else { throw .notRunning }
        guard state == .paused else { throw .unsupported }
        state = .running
    }

    func finish(_ result: Swift.Result<String, AgenticError>) {
        task = nil
        switch result {
        case .success: state = .completed
        case .failure(.cancelled): state = .cancelled
        case .failure: state = .failed
        }
    }
}

extension OperationLifecycle where Result == Swift.Result<String, AgenticError>, Success == Result {
    func start() async -> Swift.Result<String, AgenticError> {
        guard state.canStart else { return .failure(.busy) }
        let work = Task { await run() }
        task = work
        state = .running
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private func run() async -> Swift.Result<String, AgenticError> {
        let result: Swift.Result<String, AgenticError>
        do {
            let response = await session.respond(
                to: spec.inputJSON.rawValue, instructions: try instructions(),
                schema: try strategy.schema(for: Specification.outputSchema), for: id)
            result = strategy.result(from: response)
        } catch {
            result = .failure(error)
        }
        finish(result)
        return result
    }
}

extension OperationLifecycle where Result == AsyncStream<Swift.Result<String, AgenticError>>, Success == Void {
    func start() async -> AsyncStream<Swift.Result<String, AgenticError>> {
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
                to: spec.inputJSON.rawValue, instructions: try instructions(),
                schema: try strategy.schema(for: Specification.outputSchema), for: id
            ) { text in
                output.yield(.success(text))
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
