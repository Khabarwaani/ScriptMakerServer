import Foundation
import Synchronization
import AgentAtom

/// An internal base engine that provides shared process execution, metadata tracking, single-flight concurrency,
/// and conversation context tracking across sequential executions.
final class TerminalSessionEngine: Sendable {
    let configuration: TerminalAgentConfiguration
    let runner: TerminalProcessRunner
    private let state = Mutex(State())

    struct State: Sendable {
        var isBusy = false
        var records: [AgenticExecutionMetadata] = []
        var activeConversationID: String?
        var managedProcess: TerminalProcessRunner.ManagedProcess?
    }

    var executionMetadata: [AgenticExecutionMetadata] {
        state.withLock { $0.records }
    }

    var activeConversationID: String? {
        state.withLock { $0.activeConversationID }
    }

    init?(configuration: TerminalAgentConfiguration, runner: TerminalProcessRunner = TerminalProcessRunner()) {
        guard let resolvedURL = runner.resolveExecutable(
            named: configuration.executablePath,
            additionalSearchPaths: configuration.additionalSearchPaths
        ) else {
            return nil
        }
        var updated = configuration
        updated.resolvedURL = resolvedURL
        self.configuration = updated
        self.runner = runner
        if let initialID = configuration.conversationID {
            state.withLock { $0.activeConversationID = initialID }
        }
    }

    /// Sets or updates the active conversation ID.
    func setConversationID(_ id: String?) {
        state.withLock { $0.activeConversationID = id }
    }

    /// Clears execution metadata without terminating the active in-memory process.
    func clearMemory() {
        state.withLock {
            $0.records.removeAll()
        }
    }

    /// Purges all session memory, terminates any running in-memory process, and resets all engine state.
    func purgeMemory() {
        state.withLock {
            $0.records.removeAll()
            $0.activeConversationID = nil
            $0.managedProcess?.terminate()
            $0.managedProcess = nil
        }
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
                if configuration.memoryRetentionPolicy == .clear {
                    state.records.removeAll()
                } else {
                    state.records.append(record)
                }
                state.isBusy = false
            }
        }

        guard let executableURL = configuration.resolvedURL else {
            throw AgenticError.operationFailed(reason: "Executable not resolved at '\(configuration.executablePath)'")
        }

        switch configuration.persistenceMode {
        case .persistentStdio:
            return try await executeWithPersistentProcess(
                executableURL: executableURL,
                arguments: arguments,
                yield: yield
            )
        case .daemon, .ephemeral:
            return try await runner.streamLines(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: configuration.workingDirectory,
                yield: yield
            )
        }
    }

    private func executeWithPersistentProcess(
        executableURL: URL,
        arguments: [String],
        yield: (String) async -> Void
    ) async throws -> TerminalProcessRunner.ExecutionResult {
        // Reuse existing running in-memory process, or spawn and retain a new one
        let process: TerminalProcessRunner.ManagedProcess = try state.withLock { state in
            if let existing = state.managedProcess, existing.isRunning {
                return existing
            }
            let spawned = try runner.spawnProcess(
                executableURL: executableURL,
                arguments: configuration.extraArguments,
                currentDirectoryURL: configuration.workingDirectory
            )
            state.managedProcess = spawned
            return spawned
        }

        // If the process immediately exited on spawn (e.g. CLI that requires batch mode or runs to completion), fallback to streamLines
        if !process.isRunning {
            state.withLock { $0.managedProcess = nil }
            return try await runner.streamLines(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: configuration.workingDirectory,
                yield: yield
            )
        }

        let inputPrompt = arguments.last ?? ""
        if let inputData = (inputPrompt + "\n").data(using: .utf8) {
            try? process.stdinHandle.write(contentsOf: inputData)
        }

        let stdout = try await process.readLinesUntil(
            stopCondition: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("\"type\":\"result\"") || trimmed.contains("\"type\":\"completed\"") || trimmed.contains("\"result\":") {
                    return true
                }
                if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) && !trimmed.contains("\"type\":\"text\"") && !trimmed.contains("\"type\":\"delta\"") && !trimmed.contains("\"delta\":") {
                    return true
                }
                return false
            },
            onCancel: { process.terminate() },
            yield: yield
        )

        let exitCode = process.terminationStatus ?? 0
        return TerminalProcessRunner.ExecutionResult(
            stdout: stdout,
            stderr: "",
            exitCode: exitCode
        )
    }
}
