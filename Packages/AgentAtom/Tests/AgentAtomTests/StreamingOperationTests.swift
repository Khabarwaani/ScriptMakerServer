import AgentAtom
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct StreamingOperationTests {
    @Test
    func newestSnapshotBufferAndFinalResult() async throws {
        let session = TestSession(configuration: .init(snapshots: ["{", "{\"points\":", "latest partial"]), blocked: true)
        let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        let stream = await operation.execute()
        await session.snapshotsSent.wait()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .success("latest partial"))
        await session.release.open()
        #expect(await iterator.next() == .success(KeyPointsSpec.namedJSON))
        #expect(await iterator.next() == nil)
        #expect(await operation.state == .completed)
        #expect(session.executionMetadata.count == 1)
        #expect(await last(in: operation.execute()) == .success(KeyPointsSpec.namedJSON))
        #expect(session.executionMetadata.count == 2)
    }

    @Test
    func declaredFailureOnlyAllowedForFailableStream() async {
        let configuration = TestSession.Configuration(responses: [.success(KeyPointsSpec.failureJSON)], snapshots: ["partial"])
        let normal = StreamingAgenticOperation(spec: KeyPointsSpec(input: "Hello"), session: TestSession(configuration: configuration))
        let failable = FailableStreamingAgenticOperation(spec: KeyPointsSpec(input: "Hello"), session: TestSession(configuration: configuration))
        #expect(await last(in: normal.execute()) == .failure(.operationFailed(reason: "Invalid failure response.")))
        #expect(await last(in: failable.execute()) == .failure(.generationFailed(reason: "The input does not support three meaningful points.")))
        #expect(await normal.state == .failed)
        #expect(await failable.state == .failed)
    }

    @Test
    func providerFailureAndRerun() async {
        let error = AgenticError.operationFailed(reason: "Provider stopped.")
        let session = TestSession(configuration: .init(responses: [.failure(error), .success("done")]))
        let operation = FailableStreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        #expect(await last(in: operation.execute()) == .failure(error))
        #expect(await operation.state == .failed)
        #expect(await last(in: operation.execute()) == .success("done"))
        #expect(session.executionMetadata.count == 2)
    }

    @Test
    func directCancellationKeepsTerminalFailureDeliverable() async {
        let session = TestSession(blocked: true)
        let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        let stream = await operation.execute()
        await session.started.wait()
        #expect(await last(in: operation.execute()) == .failure(.busy))
        await operation.cancel()
        #expect(await operation.state == .cancelling)
        #expect(await last(in: operation.execute()) == .failure(.busy))
        #expect(session.executionMetadata.isEmpty)
        await session.release.open()
        #expect(await last(in: stream) == .failure(.cancelled))
        #expect(await operation.state == .cancelled)
        #expect(await last(in: operation.execute()) == .success(KeyPointsSpec.namedJSON))
    }

    @Test
    func consumerCancellationStopsProducer() async throws {
        let session = TestSession(blocked: true)
        let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        let stream = await operation.execute()
        let consumer = Task { for await _ in stream {} }
        await session.started.wait()
        consumer.cancel()
        await consumer.value
        await session.release.open()
        try await wait(for: operation, state: .cancelled)
        #expect(session.executionMetadata.count == 1)
        #expect(await last(in: operation.execute()) == .success(KeyPointsSpec.namedJSON))
    }

    @Test
    func earlyBreakUsesExplicitCancellation() async throws {
        let session = TestSession(configuration: .init(snapshots: ["partial"]), blocked: true)
        let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        let stream = await operation.execute()
        for await value in stream {
            #expect(value == .success("partial"))
            await operation.cancel()
            break
        }
        #expect(await operation.state == .cancelling)
        await session.release.open()
        #expect(await last(in: stream) == .failure(.cancelled))
        #expect(session.executionMetadata.count == 1)
    }

    @Test
    func cancelledCallerDoesNotLaunchStreamingProducer() async {
        let gate = TestGate()
        let session = TestSession()
        let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        let caller = Task {
            await gate.wait()
            return await operation.execute()
        }
        caller.cancel()
        await gate.open()
        #expect(await last(in: caller.value) == .failure(.cancelled))
        #expect(session.requests.isEmpty)
        #expect(await operation.state == .ready)
    }

    @Test(arguments: [false, true])
    func completedProducerReleasesOperation(cancel: Bool) async throws {
        let session = TestSession(blocked: cancel)
        var operation: StreamingAgenticOperation<KeyPointsSpec, TestSession>? = StreamingAgenticOperation(
            spec: KeyPointsSpec(input: "input"), session: session)
        weak var observer: StreamingAgenticOperation<KeyPointsSpec, TestSession>?
        observer = operation
        let stream = await operation!.execute()
        if cancel {
            await session.started.wait()
            await operation!.cancel()
            await session.release.open()
        }
        _ = await last(in: stream)
        operation = nil
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while observer != nil {
            try #require(clock.now < deadline, "A completed producer must not retain its operation.")
            await Task.yield()
        }
    }

    @Test
    func unsupportedSessionDefaultsFinishStream() async {
        let session = ResponseOnlySession()
        let operation = StreamingAgenticOperation(spec: KeyPointsSpec(input: "input"), session: session)
        #expect(await last(in: operation.execute()) == .failure(.unsupported))
        #expect(await operation.state == .failed)
        await #expect(throws: AgenticError.unsupported) { try await session.pause(operation.id) }
        await #expect(throws: AgenticError.unsupported) { try await session.resume(operation.id) }
    }

    private func last(in stream: AsyncStream<Result<String, AgenticError>>) async -> Result<String, AgenticError>? {
        var result: Result<String, AgenticError>?
        for await value in stream { result = value }
        return result
    }

    private func wait<Operation: AgenticOperationProtocol>(
        for operation: Operation, state: OperationState
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while await operation.state != state {
            try #require(clock.now < deadline, "Expected operation state: \(state)")
            await Task.yield()
        }
    }
}

private final class ResponseOnlySession: AgenticSessionProtocol {
    let configuration: Void = ()
    let executionMetadata: [AgenticExecutionMetadata] = []

    func respond(
        to input: String, instructions: String, for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> { .success(input) }
}
