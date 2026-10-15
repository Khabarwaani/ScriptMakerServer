import Foundation
import AgentAtom

/// A process runner instance that executes commands and streams lines.
public final class TerminalProcessRunner: Sendable {
    public struct ExecutionResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32
    }

    public init() {}

    /// Spawns a process and asynchronously returns lines as they are produced on standard output.
    public func streamLines(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        yield: (String) async -> Void
    ) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AgenticError.operationFailed(reason: "Failed to launch process '\(executableURL.path)': \(error.localizedDescription)")
        }

        let stderrTask = Task {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: stderrData, as: UTF8.self)
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        var fullStdout = ""
        var pendingStdout = ""
        var isEOF = false

        while !isEOF {
            if Task.isCancelled {
                process.terminate()
                throw AgenticError.cancelled
            }

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

        if !pendingStdout.isEmpty {
            await yield(pendingStdout)
        }

        process.waitUntilExit()
        let fullStderr = await stderrTask.value

        return ExecutionResult(
            stdout: fullStdout,
            stderr: fullStderr,
            exitCode: process.terminationStatus
        )
    }

    /// Resolves executable in system PATH if url does not exist directly.
    public func resolveExecutable(named name: String) -> URL? {
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
