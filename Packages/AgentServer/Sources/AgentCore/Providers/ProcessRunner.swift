import Foundation

/// Owns exactly one child. Pipe readiness callbacks avoid blocking an HTTP
/// executor; bounded chunks prevent unbounded output accumulation.
public final class ProcessRunner: ProcessRunnerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var outputContinuation: AsyncThrowingStream<Data, any Error>.Continuation?
    private var inputHandle: FileHandle?
    private let ownership: WorkerOwnershipStore?
    private var hasLaunched = false
    public struct Timing: Sendable {
        public var launched: Date?
        public var ready: Date?
        public var result: Date?
        public var exited: Date?
    }
    private var processTiming = Timing()

    public init(ownership: WorkerOwnershipStore? = nil) { self.ownership = ownership }
    public var timing: Timing {
        lock.lock(); defer { lock.unlock() }
        return processTiming
    }
    public var healthy: Bool {
        lock.lock(); defer { lock.unlock() }
        return !cancelled && (!hasLaunched || process?.isRunning == true)
    }
    public func markResultReceived() {
        lock.lock(); defer { lock.unlock() }
        if processTiming.result == nil { processTiming.result = Date() }
    }
    public func markProviderReady() {
        let first = lock.withLock {
            guard processTiming.ready == nil else { return false }
            processTiming.ready = Date()
            return true
        }
        if first, let pid = processID { ownership?.refresh(pid) }
    }
    public func send(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, let inputHandle, process?.isRunning == true else {
            throw AgentError("provider_worker_stopped", "The provider worker is no longer running.")
        }
        try inputHandle.write(contentsOf: data)
    }
    public func stop() async {
        cancel()
        while processID != nil { await terminationPause() }
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        let hasOutput = outputContinuation != nil
        lock.unlock()
        guard process != nil || hasOutput else { return }
        if let process, process.isRunning { platformSignal(process: process, graceful: true) }
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
        try await runSession(executable: executable, arguments: arguments, directory: directory,
                             input: input, timeoutSeconds: timeoutSeconds, onLine: onLine)
    }

    func runSession(
        executable: URL, arguments: [String], directory: URL? = nil,
        input: String? = nil, timeoutSeconds: Int, keepInputOpen: Bool = false,
        onStarted: @escaping @Sendable () async -> Void = {},
        onLine: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) async throws -> String {
        let child = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        // Leave Foundation's inherited working directory untouched for readiness
        // probes. A reported macOS abort occurred in this setter with no directory;
        // Objective-C exceptions bypass Swift's process-launch error handling.
        if let directory { child.currentDirectoryURL = directory }
        child.standardOutput = stdout
        child.standardError = stderr
        child.standardInput = stdin
        lock.withLock { inputHandle = stdin.fileHandleForWriting }
        configurePlatformPipe(stdin.fileHandleForWriting)
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        let existingPath = environment["PATH"] ?? ""
        let standardPaths = Self.platformStandardPaths
        let separator = Self.platformPathSeparator
        let existingSegments = existingPath.split(separator: separator).map(String.init)
        let missingPaths = standardPaths.filter { !existingSegments.contains($0) }
        if !missingPaths.isEmpty {
            let combined = (missingPaths + [existingPath]).filter { !$0.isEmpty }
            environment["PATH"] = combined.joined(separator: String(separator))
        }
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
            clearProcess()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            try? stdin.fileHandleForWriting.close()
        }
        let (exitEvents, exitContinuation) = AsyncStream<Int32>.makeStream()
        child.terminationHandler = { [self] process in
            lock.withLock { processTiming.exited = Date() }
            exitContinuation.yield(process.terminationStatus)
            exitContinuation.finish()
        }
        try launch(child)
        await onStarted()
        let timeout = Task { [self] in
            guard timeoutSeconds > 0 else { return }
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
        }
        let inputTask = Task.detached {
            if let input { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
            if !keepInputOpen { try stdin.fileHandleForWriting.close() }
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
                    if keepInputOpen { continue }
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
                if !keepInputOpen { finalText += line }
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
        do {
            try lock.withLock {
                guard !cancelled else { throw CancellationError() }
                try child.run()
                process = child
                hasLaunched = true
                processTiming.launched = Date()
            }
            do { try ownership?.register(child.processIdentifier) } catch {
                platformSignal(process: child, graceful: false)
                child.waitUntilExit()
                lock.withLock { process = nil }
                throw error
            }
        } catch {
            if error is CancellationError { throw error }
            if let error = error as? AgentError { throw error }
            throw AgentError(
                "process_launch_failed", "The configured provider process could not be launched.")
        }
    }
    private func clearProcess() {
        lock.lock()
        let pid = process?.processIdentifier
        process = nil
        inputHandle = nil
        outputContinuation = nil
        lock.unlock()
        if let pid { ownership?.unregister(pid) }
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
    public var processID: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return process.flatMap { $0.isRunning ? $0.processIdentifier : nil }
    }
    public var residentMemoryBytes: UInt64 {
        guard let pid = processID else { return 0 }
        return platformResidentMemory(pid: pid)
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
        if let process, process.isRunning { platformSignal(process: process, graceful: false) }
    }
}
