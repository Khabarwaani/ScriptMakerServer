import Foundation
import AgentAtom

/// Robust, asynchronous process runner for terminal CLI agent tools.
/// Handles stdout streaming, stderr capture, and cancellation.
enum TerminalProcessRunner {
    struct ExecutionResult: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Spawns a process and asynchronously returns lines as they are produced on standard output.
    static func streamLines(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        yield: (String) async -> Void
    ) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Buffer to accumulate output across lines
        final class OutputState: @unchecked Sendable {
            var fullStdout = ""
            var fullStderr = ""
            var pendingStdout = ""
        }
        let state = OutputState()

        do {
            try process.run()
        } catch {
            throw AgenticError.operationFailed(reason: "Failed to launch process '\(executableURL.path)': \(error.localizedDescription)")
        }

        // Read stderr concurrently
        let stderrTask = Task {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: stderrData, as: UTF8.self)
        }

        // Stream stdout by reading chunks
        let stdoutHandle = stdoutPipe.fileHandleForReading
        var isEOF = false

        while !isEOF {
            if Task.isCancelled {
                process.terminate()
                throw AgenticError.cancelled
            }

            // readData of up to 4096 bytes
            let chunk = stdoutHandle.availableData
            if chunk.isEmpty {
                isEOF = true
            } else {
                let text = String(decoding: chunk, as: UTF8.self)
                state.fullStdout.append(text)
                state.pendingStdout.append(text)

                while let newlineIndex = state.pendingStdout.firstIndex(of: "\n") {
                    let line = String(state.pendingStdout[..<newlineIndex])
                    state.pendingStdout.removeSubrange(...newlineIndex)
                    await yield(line)
                }
            }
        }

        // Flush any remaining pending stdout
        if !state.pendingStdout.isEmpty {
            let remaining = state.pendingStdout
            state.pendingStdout = ""
            await yield(remaining)
        }

        process.waitUntilExit()
        state.fullStderr = await stderrTask.value

        return ExecutionResult(
            stdout: state.fullStdout,
            stderr: state.fullStderr,
            exitCode: process.terminationStatus
        )
    }

    /// Runs a process to completion, returning the complete stdout, stderr, and exit code.
    static func runToCompletion(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) async throws -> ExecutionResult {
        try await streamLines(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            yield: { _ in }
        )
    }

    /// Resolves executable in system PATH if url does not exist directly.
    static func resolveExecutable(named name: String) -> URL? {
        if name.hasPrefix("/") || name.hasPrefix("./") {
            let url = URL(fileURLWithPath: name)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        let searchPaths = envPath.split(separator: ":").map(String.init)
        for searchPath in searchPaths {
            let candidate = URL(fileURLWithPath: searchPath).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
