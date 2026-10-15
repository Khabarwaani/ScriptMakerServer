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

        var fullStdout = ""
        var pendingStdout = ""

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
                fullStdout.append(text)
                pendingStdout.append(text)

                while let newlineIndex = pendingStdout.firstIndex(of: "\n") {
                    let line = String(pendingStdout[..<newlineIndex])
                    pendingStdout.removeSubrange(...newlineIndex)
                    await yield(line)
                }
            }
        }

        // Flush any remaining pending stdout
        if !pendingStdout.isEmpty {
            let remaining = pendingStdout
            pendingStdout = ""
            await yield(remaining)
        }

        process.waitUntilExit()
        let fullStderr = await stderrTask.value

        return ExecutionResult(
            stdout: fullStdout,
            stderr: fullStderr,
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
        #if os(Windows)
        let extensions = ["", ".exe", ".cmd", ".bat"]
        let pathSeparator: Character = ";"
        let defaultPath = "C:\\Windows\\System32;C:\\Windows"
        #else
        let extensions = [""]
        let pathSeparator: Character = ":"
        let defaultPath = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        #endif

        if name.hasPrefix("/") || name.hasPrefix("./") || (name.count > 1 && name.contains(":")) {
            for ext in extensions {
                let candidatePath = ext.isEmpty ? name : name + ext
                let url = URL(fileURLWithPath: candidatePath)
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
            return nil
        }

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? defaultPath
        let searchPaths = envPath.split(separator: pathSeparator).map(String.init)
        for searchPath in searchPaths {
            for ext in extensions {
                let fullName = ext.isEmpty ? name : name + ext
                let candidate = URL(fileURLWithPath: searchPath).appendingPathComponent(fullName)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
