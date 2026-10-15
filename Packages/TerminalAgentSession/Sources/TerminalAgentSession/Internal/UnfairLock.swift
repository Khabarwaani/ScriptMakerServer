import Foundation

/// A lightweight, Sendable unfair lock for thread-safe state synchronization across supported macOS versions.
final class UnfairLock: @unchecked Sendable {
    private let pointer: os_unfair_lock_t

    init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        os_unfair_lock_lock(pointer)
        defer { os_unfair_lock_unlock(pointer) }
        return try body()
    }
}
