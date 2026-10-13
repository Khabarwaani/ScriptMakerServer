import Foundation

/// A kernel-owned lock identifies the running server without stale PID files.
/// Keep this object alive until HTTP shutdown has completed.
public final class ServerInstance: Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { Self.closePlatformDescriptor(descriptor) }

    public static func start(
        port: Int, timeoutSeconds: Int, replaceExisting: Bool = true
    ) async throws -> ServerInstance {
        let descriptor = try openPlatformLock(port: port)
        do {
            if replaceExisting {
                _ = try await stopPlatformOwner(descriptor: descriptor, timeoutSeconds: timeoutSeconds)
            }
            try applyPlatformWriteLock(descriptor: descriptor)
            if replaceExisting {
                try await reclaimPort(port, timeoutSeconds: timeoutSeconds)
            }
            return ServerInstance(descriptor: descriptor)
        } catch {
            closePlatformDescriptor(descriptor)
            throw error
        }
    }

    public static func isPortAvailable(_ port: Int) -> Bool {
        checkPortAvailable(port)
    }

    /// Returns false when no managed instance is running. Never force-kills.
    @discardableResult
    public static func stop(port: Int, timeoutSeconds: Int) async throws -> Bool {
        let descriptor = try openPlatformLock(port: port)
        defer { closePlatformDescriptor(descriptor) }
        return try await stopPlatformOwner(descriptor: descriptor, timeoutSeconds: timeoutSeconds)
    }

    public enum InstanceError: Error, CustomStringConvertible {
        case unsafeLockFile, lockInspectionFailed, unverifiedProcess, signalFailed
        case shutdownTimedOut, concurrentStartup, portReclamationFailed

        public var description: String {
            switch self {
            case .unsafeLockFile: "Cannot open a secure server instance lock."
            case .lockInspectionFailed: "Cannot inspect the server instance lock."
            case .unverifiedProcess:
                "The previous process could not be verified as AgentServer; it was not stopped."
            case .signalFailed: "Could not request graceful server shutdown."
            case .shutdownTimedOut:
                "The previous server did not shut down in time; no replacement was started."
            case .concurrentStartup: "Another server started concurrently; retry the command."
            case .portReclamationFailed:
                "Existing processes listening on the configured port could not be terminated, or the port remained occupied."
            }
        }
    }
}
