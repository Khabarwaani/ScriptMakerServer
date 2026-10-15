import Foundation
import AgentAtom

/// An internal process runner instance that executes commands and streams lines.
final class TerminalProcessRunner: Sendable {
    struct ExecutionResult: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    init() {}

    /// Spawns a process and asynchronously returns lines as they are produced on standard output.
    func streamLines(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        yield: (String) async -> Void
    ) async throws -> ExecutionResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        configure(
            process: process,
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        do {
            try process.run()
        } catch {
            throw mapLaunchError(error, path: executableURL.path)
        }

        let stderrTask = Task { readStream(from: stderrPipe.fileHandleForReading) }
        let stdout = try await readAndStreamLines(from: stdoutPipe.fileHandleForReading, process: process, yield: yield)

        process.waitUntilExit()
        let stderr = await stderrTask.value

        return ExecutionResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    /// Resolves executable in system PATH and additional search paths if url does not exist directly.
    func resolveExecutable(named name: String, additionalSearchPaths: [String] = []) -> URL? {
        if isExplicitPath(name) {
            return searchExtensions(basePath: name)
        }
        return searchSystemPath(named: name, additionalSearchPaths: additionalSearchPaths)
    }

    // MARK: - Private Decomposed Helpers

    private func configure(
        process: Process,
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        currentDirectoryURL: URL?,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) {
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    private func readStream(from handle: FileHandle) -> String {
        let data = handle.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func readAndStreamLines(
        from handle: FileHandle,
        process: Process,
        yield: (String) async -> Void
    ) async throws -> String {
        var fullStdout = ""
        var pendingStdout = ""

        while true {
            if Task.isCancelled {
                process.terminate()
                throw AgenticError.cancelled
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else { break }

            let text = String(decoding: chunk, as: UTF8.self)
            fullStdout.append(text)
            pendingStdout.append(text)

            while let newlineIndex = pendingStdout.firstIndex(of: "\n") {
                let line = String(pendingStdout[..<newlineIndex])
                pendingStdout.removeSubrange(...newlineIndex)
                await yield(line)
            }
        }

        if !pendingStdout.isEmpty {
            await yield(pendingStdout)
        }

        return fullStdout
    }

    private func mapLaunchError(_ error: Error, path: String) -> AgenticError {
        (error as? AgenticError) ?? .operationFailed(reason: error.localizedDescription)
    }

    private var executableExtensions: [String] {
        #if os(Windows)
        ["", ".exe", ".cmd", ".bat"]
        #else
        [""]
        #endif
    }

    private var pathSeparator: Character {
        #if os(Windows)
        ";"
        #else
        ":"
        #endif
    }

    private var defaultSystemPath: String {
        #if os(Windows)
        "C:\\Windows\\System32;C:\\Windows"
        #else
        "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
        #endif
    }

    private func isExplicitPath(_ name: String) -> Bool {
        name.hasPrefix("/") || name.hasPrefix("./") || (name.count > 1 && name.contains(":"))
    }

    private func searchExtensions(basePath: String) -> URL? {
        for ext in executableExtensions {
            let candidate = ext.isEmpty ? basePath : basePath + ext
            let url = URL(fileURLWithPath: candidate)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func searchSystemPath(named name: String, additionalSearchPaths: [String] = []) -> URL? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? defaultSystemPath
        let envSearchPaths = envPath.split(separator: pathSeparator).map(String.init)
        let searchPaths = additionalSearchPaths + envSearchPaths
        for searchPath in searchPaths {
            for ext in executableExtensions {
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
