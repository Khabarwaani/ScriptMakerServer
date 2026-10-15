import AgentAtom
import Foundation
#if canImport(os)
import os
#else
import Synchronization
#endif

/// An explicit rendezvous, without timing-dependent sleeps.
actor TestGate {
    private var isOpen: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(open: Bool = false) { isOpen = open }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// Test-only fixtures exercise operations; they do not validate Apple's provider.
final class TestSession: AgenticSessionProtocol {
    struct Configuration: Sendable {
        var responses: [Result<String, AgenticError>] = [.success(KeyPointsSpec.namedJSON)]
        var snapshots: [String] = []
        var canPause = false
    }

    struct Request: Sendable {
        let input: String
        let instructions: String
        let schema: JSONString
        let operation: ObjectIdentifier
    }

    private struct State: Sendable {
        var busy = false
        var requests: [Request] = []
        var records: [AgenticExecutionMetadata] = []
    }

    let configuration: Configuration
    let started = TestGate()
    let snapshotsSent = TestGate()
    let rerunStarted = TestGate()
    let paused = TestGate()
    let resumed = TestGate()
    let release: TestGate
    let releaseRerun: TestGate
    let releasePause: TestGate
    let releaseResume: TestGate
    #if canImport(os)
    private let state = OSAllocatedUnfairLock(initialState: State())
    #else
    private let state = Mutex(State())
    #endif

    init(
        configuration: Configuration = Configuration(), blocked: Bool = false,
        blockPause: Bool = false, blockResume: Bool = false, blockRerun: Bool = false
    ) {
        self.configuration = configuration
        release = TestGate(open: !blocked)
        releaseRerun = TestGate(open: !blockRerun)
        releasePause = TestGate(open: !blockPause)
        releaseResume = TestGate(open: !blockResume)
    }

    var requests: [Request] { state.withLock { $0.requests } }
    var executionMetadata: [AgenticExecutionMetadata] { state.withLock { $0.records } }

    func respond(
        to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier
    ) async -> Result<String, AgenticError> {
        await stream(to: input, instructions: instructions, schema: schema, for: operation) { _ in }
    }

    func stream(
        to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier,
        yield: @Sendable (String) async -> Void
    ) async -> Result<String, AgenticError> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        let index = state.withLock { value -> Int? in
            guard !value.busy else { return nil }
            value.busy = true
            let index = value.requests.count
            value.requests.append(Request(input: input, instructions: instructions, schema: schema, operation: operation))
            return index
        }
        guard let index else { return .failure(.busy) }
        let executionID = UUID()
        defer {
            state.withLock {
                $0.records.append(AgenticExecutionMetadata(operationID: operation, executionID: executionID))
                $0.busy = false
            }
        }
        await started.open()
        if index > 0 { await rerunStarted.open() }
        for snapshot in configuration.snapshots { await yield(snapshot) }
        await snapshotsSent.open()
        // Deliberately permit delayed cleanup to test cancellation admission rules.
        await (index == 0 ? release : releaseRerun).wait()
        guard !Task.isCancelled else { return .failure(.cancelled) }
        return configuration.responses[min(index, configuration.responses.count - 1)]
    }

    func pause(_ operation: ObjectIdentifier) async throws(AgenticError) {
        guard configuration.canPause else { throw .unsupported }
        await paused.open()
        await releasePause.wait()
    }

    func resume(_ operation: ObjectIdentifier) async throws(AgenticError) {
        guard configuration.canPause else { throw .unsupported }
        await resumed.open()
        await releaseResume.wait()
    }
}
