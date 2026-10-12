import Foundation

/// Defines the contract for executing child CLI processes, streaming lines,
/// reporting resident memory, and managing scoped cancellation.
public protocol ProcessRunnerProtocol: AnyObject, Sendable {
    func run(
        executable: URL,
        arguments: [String],
        directory: URL?,
        input: String?,
        timeoutSeconds: Int,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws -> String

    func cancel()
    var processID: Int32? { get }
    var residentMemoryBytes: UInt64 { get }
}

/// Internal contract defining the hooks that platform extensions must provide for ProcessRunner.
protocol ProcessRunnerPlatformHook: Sendable {
    func configurePlatformPipe(_ handle: FileHandle)
    func platformResidentMemory(pid: Int32) -> UInt64
    func platformSignal(process: Process, graceful: Bool)
    static var platformPathSeparator: Character { get }
    static var platformStandardPaths: [String] { get }
    static var platformExecutableExtensions: [String] { get }
}

/// Contract defining the host resource sampling hook.
protocol ResourcePlatformDelegate: Sendable {
    static func samplePlatform() -> SystemResources
}

/// Contract defining single-instance server locking and owner process termination.
protocol LockPlatformDelegate: Sendable {
    static func openPlatformLock(port: Int) throws -> Int32
    static func stopPlatformOwner(descriptor: Int32, timeoutSeconds: Int) async throws -> Bool
    static func applyPlatformWriteLock(descriptor: Int32) throws
}
