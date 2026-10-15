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
        try InstructionAssembler(strategy: strategy).assemble(spec: spec)
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
        switch result {
        case .success: state = .completed
        case .failure(.cancelled): state = .cancelled
        case .failure: state = .failed
        }
    }
}
