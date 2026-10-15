import Foundation

actor OperationRunner<Session: AgenticSessionProtocol> {
    private let operationID: UUID
    private let session: Session
    private var producer: Task<Result<String, AgenticOperationError>, Never>?

    var isExecuting: Bool { producer != nil }

    init(operationID: UUID, session: Session) {
        self.operationID = operationID
        self.session = session
    }

    func execute(
        input: String, instructions: Result<String, any Error>, allowsFailure: Bool
    ) async -> Result<String, AgenticOperationError> {
        let assembled: String
        switch prepare(instructions) {
        case .success(let value): assembled = value
        case .failure(let error): return .failure(error)
        }
        let worker = Task {
            let response = await session.generate(input: input, instructions: assembled, operationID: operationID)
            if Task.isCancelled { return Result<String, AgenticOperationError>.failure(.cancelled) }
            return decode(response, allowsFailure: allowsFailure)
        }
        producer = worker
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        producer = nil
        return result
    }

    func stream(
        input: String, instructions: Result<String, any Error>, allowsFailure: Bool
    ) -> AsyncStream<Result<String, AgenticOperationError>> {
        let (results, continuation) = AsyncStream<Result<String, AgenticOperationError>>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let assembled: String
        switch prepare(instructions) {
        case .success(let value): assembled = value
        case .failure(let error):
            continuation.yield(.failure(error))
            continuation.finish()
            return results
        }
        let worker = Task {
            defer {
                producer = nil
                continuation.finish()
            }
            let response = await session.stream(input: input, instructions: assembled, operationID: operationID) { snapshot in
                if case .terminated = continuation.yield(.success(snapshot)) {
                    throw AgenticOperationError.cancelled
                }
            }
            let result: Result<String, AgenticOperationError>
            if Task.isCancelled {
                result = .failure(.cancelled)
            } else {
                result = decode(response, allowsFailure: allowsFailure)
            }
            continuation.yield(result)
            return result
        }
        producer = worker
        continuation.onTermination = { termination in
            if case .cancelled = termination { worker.cancel() }
        }
        return results
    }

    func cancel() {
        producer?.cancel()
    }

    func pause() async throws(AgenticOperationError) {
        guard producer != nil else { throw .notRunning }
        try await session.pause(operationID: operationID)
    }

    func resume() async throws(AgenticOperationError) {
        guard producer != nil else { throw .notRunning }
        try await session.resume(operationID: operationID)
    }

    private func prepare(_ instructions: Result<String, any Error>) -> Result<String, AgenticOperationError> {
        guard producer == nil else { return .failure(.busy) }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        return instructions.mapError { ($0 as? AgenticOperationError) ?? .invalidInstructions }
    }

    private func decode(
        _ response: Result<String, AgenticOperationError>, allowsFailure: Bool
    ) -> Result<String, AgenticOperationError> {
        guard case .success(let text) = response else { return response }
        let data = Data(text.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["domain"] as? String == "AgentAtom.Operation" else {
            return response
        }
        guard allowsFailure,
              let failure = try? JSONDecoder().decode(OperationFailure.self, from: data),
              failure.code == 422 else {
            return .failure(.invalidResponse)
        }
        return .failure(.generationFailed(reason: failure.reason))
    }
}
