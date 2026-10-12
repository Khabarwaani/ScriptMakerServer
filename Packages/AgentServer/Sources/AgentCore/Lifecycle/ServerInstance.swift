import Darwin
import Foundation

/// A kernel-owned lock identifies the running server without stale PID files.
/// Keep this object alive until HTTP shutdown has completed.
public final class ServerInstance: Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    public static func start(port: Int, timeoutSeconds: Int) async throws -> ServerInstance {
        let descriptor = try openLock(port: port)
        do {
            _ = try await stopOwner(descriptor: descriptor, timeoutSeconds: timeoutSeconds)
            var lock = writeLock()
            guard fcntl(descriptor, F_SETLK, &lock) == 0 else {
                throw InstanceError.concurrentStartup
            }
            return ServerInstance(descriptor: descriptor)
        } catch {
            close(descriptor)
            throw error
        }
    }

    /// Returns false when no managed instance is running. Never force-kills.
    @discardableResult
    public static func stop(port: Int, timeoutSeconds: Int) async throws -> Bool {
        let descriptor = try openLock(port: port)
        defer { close(descriptor) }
        return try await stopOwner(descriptor: descriptor, timeoutSeconds: timeoutSeconds)
    }

    private static func openLock(port: Int) throws -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Khabarwaani-AgentServer", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directoryInfo = stat()
        guard lstat(root.path, &directoryInfo) == 0,
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_mode & 0o077 == 0 else {
            throw InstanceError.unsafeLockFile
        }
        let path = root.appendingPathComponent("port-\(port).lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw InstanceError.unsafeLockFile }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_mode & 0o077 == 0 else {
            close(descriptor)
            throw InstanceError.unsafeLockFile
        }
        // Keep the inode: deleting a lock file lets concurrent launches lock different files.
        return descriptor
    }

    private static func writeLock() -> flock {
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        return lock
    }

    private static func owner(descriptor: Int32) throws -> pid_t? {
        var lock = writeLock()
        guard fcntl(descriptor, F_GETLK, &lock) == 0 else { throw InstanceError.lockInspectionFailed }
        return lock.l_type == Int16(F_UNLCK) ? nil : lock.l_pid
    }

    private static func stopOwner(descriptor: Int32, timeoutSeconds: Int) async throws -> Bool {
        guard let pid = try owner(descriptor: descriptor) else { return false }
        // proc_pidpath is limited to 4 * MAXPATHLEN on macOS.
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
            if try owner(descriptor: descriptor) == nil { return true }
            throw InstanceError.unverifiedProcess
        }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard URL(fileURLWithPath: path).lastPathComponent == "AgentServer", pid != getpid() else {
            throw InstanceError.unverifiedProcess
        }
        guard try owner(descriptor: descriptor) == pid else { throw InstanceError.concurrentStartup }
        guard kill(pid, SIGTERM) == 0 || errno == ESRCH else { throw InstanceError.signalFailed }
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while let currentPID = try owner(descriptor: descriptor) {
            guard currentPID == pid else { throw InstanceError.concurrentStartup }
            guard ContinuousClock.now < deadline else { throw InstanceError.shutdownTimedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    public enum InstanceError: Error, CustomStringConvertible {
        case unsafeLockFile, lockInspectionFailed, unverifiedProcess, signalFailed
        case shutdownTimedOut, concurrentStartup

        public var description: String {
            switch self {
            case .unsafeLockFile: "Cannot open a secure server instance lock."
            case .lockInspectionFailed: "Cannot inspect the server instance lock."
            case .unverifiedProcess: "The previous process could not be verified as AgentServer; it was not stopped."
            case .signalFailed: "Could not request graceful server shutdown."
            case .shutdownTimedOut: "The previous server did not shut down in time; no replacement was started."
            case .concurrentStartup: "Another server started concurrently; retry the command."
            }
        }
    }
}
