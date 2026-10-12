import Darwin
import Foundation

/// Owns exactly one child. Pipe readiness callbacks avoid blocking an HTTP
/// executor; bounded chunks prevent unbounded output accumulation.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var outputContinuation: AsyncThrowingStream<Data, any Error>.Continuation?

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { signal(process, with: SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
            forceTerminate()
            lock.lock()
            let continuation = outputContinuation
            lock.unlock()
            continuation?.finish(throwing: CancellationError())
        }
    }

    public func run(
        executable: URL, arguments: [String], directory: URL? = nil,
        input: String? = nil, timeoutSeconds: Int,
        onLine: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) async throws -> String {
        let child = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = directory
        child.standardOutput = stdout
        child.standardError = stderr
        child.standardInput = stdin
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        child.environment = environment
        let (chunks, continuation) = AsyncThrowingStream<Data, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(256))
        setOutputContinuation(continuation)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else if case .dropped = continuation.yield(data) {
                continuation.finish(
                    throwing: AgentError(
                        "provider_output_limit", "Provider output exceeded the streaming buffer limit."))
            }
        }
        // Drain diagnostics without copying potentially sensitive stderr to clients.
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            try? stdin.fileHandleForWriting.close()
        }
        let (exitEvents, exitContinuation) = AsyncStream<Int32>.makeStream()
        child.terminationHandler = { process in
            exitContinuation.yield(process.terminationStatus)
            exitContinuation.finish()
        }
        try launch(child)
        let timeout = Task { [self] in
            do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
            continuation.finish(
                throwing: AgentError(
                    "execution_timeout", "Provider execution exceeded its configured timeout."))
            cancel()
            // Bound uncooperative children; only the Process object owned by this runner is targeted.
            try? await Task.sleep(for: .seconds(5))
            forceTerminate()
        }
        defer {
            timeout.cancel()
            clearProcess()
        }
        let inputTask = Task.detached {
            if let input { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
            try stdin.fileHandleForWriting.close()
        }
        var pending = Data()
        var finalText = ""
        do {
            for try await chunk in chunks {
                pending.append(chunk)
                guard pending.count <= 1_048_576 else {
                    throw AgentError("provider_output_limit", "Provider output line is too large.")
                }
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    try await onLine(line)
                    // Keep bounded output for readiness probes and text-format providers.
                    if finalText.utf8.count + line.utf8.count < 4_194_304 {
                        finalText += line + "\n"
                    } else {
                        throw AgentError(
                            "provider_output_limit", "Provider output exceeded the result limit.")
                    }
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                try await onLine(line)
                finalText += line
            }
            var iterator = exitEvents.makeAsyncIterator()
            let exitCode = await iterator.next() ?? -1
            try await inputTask.value
            guard !wasCancelled() else { throw CancellationError() }
            guard exitCode == 0 else {
                throw AgentError(
                    "provider_execution_failed",
                    "Provider execution failed. Check provider authentication and local configuration.")
            }
            return finalText
        } catch {
            cancel()
            inputTask.cancel()
            // Confirm termination before releasing the execution's resources.
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while child.isRunning && ContinuousClock.now < deadline {
                await terminationPause()
            }
            if child.isRunning { forceTerminate() }
            while child.isRunning { await terminationPause() }
            throw error
        }
    }

    private func launch(_ child: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        do {
            try child.run()
            process = child
        } catch {
            throw AgentError(
                "process_launch_failed", "The configured provider process could not be launched.")
        }
    }
    private func clearProcess() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    private func terminationPause() async {
        // A cancelled execution must still wait without spinning its executor.
        await Task.detached { try? await Task.sleep(for: .milliseconds(50)) }.value
    }
    private func setOutputContinuation(_ continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        lock.lock()
        outputContinuation = continuation
        lock.unlock()
    }
    public var processID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return process.flatMap { $0.isRunning ? $0.processIdentifier : nil }
    }
    public var residentMemoryBytes: UInt64 {
        guard let pid = processID else { return 0 }
        var info = proc_taskinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) > 0
        else { return 0 }
        return info.pti_resident_size
    }
    private func wasCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    private func forceTerminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { signal(process, with: SIGKILL) }
    }
    private func signal(_ process: Process, with signal: Int32) {
        let pid = process.processIdentifier
        // Foundation creates a fresh process group on macOS. Verify ownership
        // before targeting the group, so cancellation also stops its tool children.
        if getpgid(pid) == pid { _ = kill(-pid, signal) } else { _ = kill(pid, signal) }
    }
}
