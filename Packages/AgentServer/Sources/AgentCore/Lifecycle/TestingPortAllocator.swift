import Foundation
import NIOCore
import NIOPosix

/// Automatic port selection for real test servers. The operation must retain
/// ownership for its lifetime and report only startup collisions as portInUse.
public enum TestingPortAllocator {
    public enum AllocationError: Error, CustomStringConvertible {
        case portInUse
        case exhausted(range: ClosedRange<Int>, attempts: Int)

        public var description: String {
            switch self {
            case .portInUse: "The test-server port is already in use."
            case .exhausted(let range, let attempts):
                "No test-server port available in \(range.lowerBound)–\(range.upperBound) after \(attempts) attempts."
            }
        }
    }

    public static func withAvailablePort<Result: Sendable>(
        configuration: TestingPortConfiguration,
        host: String = "127.0.0.1",
        preferredPort: Int? = nil,
        operation: (Int) async throws -> Result
    ) async throws -> Result {
        let candidates: [Int]
        if let preferredPort {
            guard configuration.range.contains(preferredPort) else {
                throw ServerConfiguration.ConfigurationError.invalidPort
            }
            candidates = [preferredPort] + configuration.range.filter { $0 != preferredPort }.shuffled()
        } else {
            candidates = Array(configuration.range).shuffled()
        }
        return try await attempt(
            configuration: configuration, candidates: candidates,
            isAvailable: { try await isAvailable(host: host, port: $0) }, operation: operation)
    }

    /// Bind/listen on the actual interface instead of assuming a failed connect
    /// means the port is free. Startup still handles races after this socket closes.
    public static func isAvailable(host: String = "127.0.0.1", port: Int) async throws -> Bool {
        do {
            let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .bind(host: host, port: port).get()
            try await channel.close().get()
            return true
        } catch {
            if isAddressInUse(error) { return false }
            throw error
        }
    }

    public static func isAddressInUse(_ error: any Error) -> Bool {
        guard let error = error as? IOError else { return false }
        #if os(Windows)
        return error.errnoCode == 10048 // WSAEADDRINUSE
        #else
        return error.errnoCode == POSIXErrorCode.EADDRINUSE.rawValue
        #endif
    }

    // Deterministic boundary for retry tests; production always shuffles candidates.
    static func attempt<Result: Sendable>(
        configuration: TestingPortConfiguration,
        candidates: [Int],
        isAvailable: (Int) async throws -> Bool,
        operation: (Int) async throws -> Result
    ) async throws -> Result {
        var tried: Set<Int> = []
        for port in candidates where configuration.range.contains(port) && !tried.contains(port) {
            guard tried.count < configuration.maxAttempts else { break }
            try Task.checkCancellation()
            tried.insert(port)
            guard try await isAvailable(port) else { continue }
            do { return try await operation(port) }
            catch AllocationError.portInUse { continue }
        }
        throw AllocationError.exhausted(range: configuration.range, attempts: tried.count)
    }
}
