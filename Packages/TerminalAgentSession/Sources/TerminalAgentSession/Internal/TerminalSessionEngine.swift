import Foundation
import Synchronization
import AgentAtom

/// An internal base engine that provides shared process execution, metadata tracking, and single-flight concurrency.
final class TerminalSessionEngine: Sendable {
    let configuration: TerminalAgentConfiguration
    let runner: TerminalProcessRunner
    private let state = Mutex(State())

    struct State: Sendable {
        var isBusy = false
        var records: [AgenticExecutionMetadata] = []
    }

    var executionMetadata: [AgenticExecutionMetadata] {
        state.withLock { $0.records }
    }

    init?(configuration: TerminalAgentConfiguration, runner: TerminalProcessRunner = TerminalProcessRunner()) {
        guard let resolvedURL = runner.resolveExecutable(named: configuration.executablePath) else {
            return nil
        }
        var updated = configuration
        updated.resolvedURL = resolvedURL
        self.configuration = updated
        self.runner = runner
    }

    /// Executes CLI arguments with single-run admission, timing metadata recording, and streaming callback.
    func execute(
        arguments: [String],
        operation: ObjectIdentifier,
        defaultModel: String,
        yield: (String) async -> Void
    ) async throws -> TerminalProcessRunner.ExecutionResult {
        guard !Task.isCancelled else { throw AgenticError.cancelled }

        let admitted = state.withLock { state -> Bool in
            guard !state.isBusy else { return false }
            state.isBusy = true
            return true
        }
        guard admitted else { throw AgenticError.busy }

        let startTime = ContinuousClock().now
        let executionID = UUID()

        defer {
            let record = AgenticExecutionMetadata(
                operationID: operation,
                executionID: executionID,
                modelIdentifier: configuration.metadata.contains(.modelIdentifier) ? (configuration.model ?? defaultModel) : nil,
                duration: configuration.metadata.contains(.duration) ? startTime.duration(to: ContinuousClock().now) : nil,
                promptTokens: nil,
                completionTokens: nil
            )
            state.withLock { state in
                state.records.append(record)
                state.isBusy = false
            }
        }

        guard let executableURL = configuration.resolvedURL else {
            throw AgenticError.operationFailed(reason: "Executable not resolved at '\(configuration.executablePath)'")
        }

        return try await runner.streamLines(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: configuration.workingDirectory,
            yield: yield
        )
    }
}
