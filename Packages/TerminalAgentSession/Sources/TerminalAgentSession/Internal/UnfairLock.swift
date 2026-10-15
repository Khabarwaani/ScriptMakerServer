import Foundation

/// A lightweight, Sendable thread-safe lock for state synchronization across macOS, Linux, and Windows.
final class UnfairLock: @unchecked Sendable {
    private let lock = NSLock()

    init() {}

    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
