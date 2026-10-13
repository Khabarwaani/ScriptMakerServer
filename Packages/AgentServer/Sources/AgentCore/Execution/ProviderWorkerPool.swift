import Foundation

public struct WorkerPoolSnapshot: Codable, Sendable {
    public let retained: Int
    public let idle: Int
    public let busy: Int
    public let temporary: Int
    public let retiring: Int
    public let capacity: Int
    public let max_processes: Int
    public let resident_memory_bytes: UInt64
}

/// Value state owned by ExecutionManager. Reservations count before processes
/// launch; an eviction is fully stopped before its replacement can launch.
struct ProviderWorkerPool {
    struct Key: Hashable, Sendable {
        let provider: String
        let agent: String
        let version: String
    }
    struct Lease: Sendable {
        let id: UUID
        let worker: any ProviderWorker
        let reused: Bool
        let evicted: (any ProviderWorker)?
    }
    private struct Slot {
        let key: Key
        let worker: any ProviderWorker
        let retained: Bool
        var busy = true
        var retiring = false
        var lastUsed: UInt64
        var evicted: (any ProviderWorker)?
    }
    let capacity: Int
    let maxProcesses: Int
    private var sequence: UInt64 = 0
    private var slots: [UUID: Slot] = [:]

    init(capacity: Int, maxProcesses: Int) {
        self.capacity = min(max(0, capacity), maxProcesses)
        self.maxProcesses = maxProcesses
    }
    mutating func acquire(key: Key, make: () throws -> any ProviderWorker) throws -> Lease? {
        sequence += 1
        if let id = slots.first(where: { !$0.value.busy && !$0.value.retiring && $0.value.key == key && $0.value.worker.healthy })?.key {
            slots[id]!.busy = true
            slots[id]!.lastUsed = sequence
            return Lease(id: id, worker: slots[id]!.worker, reused: true, evicted: nil)
        }
        let oldest = slots.filter { !$0.value.busy && !$0.value.retiring }.min {
            if $0.value.worker.healthy != $1.value.worker.healthy { return !$0.value.worker.healthy }
            return $0.value.lastUsed < $1.value.lastUsed
        }
        if slots.count >= maxProcesses && oldest == nil { return nil }
        let worker = try make()
        let retainedCount = slots.values.filter { $0.retained && !$0.retiring }.count
        let mustEvict = slots.count >= maxProcesses || (worker.reusable && retainedCount >= capacity && capacity > 0)
        var evicted: (any ProviderWorker)?
        var retained = worker.reusable && retainedCount < capacity
        if mustEvict, let oldest {
            evicted = oldest.value.worker
            retained = worker.reusable && capacity > 0 && (retainedCount < capacity || oldest.value.retained)
            slots[oldest.key] = nil
        }
        let id = UUID()
        slots[id] = Slot(key: key, worker: worker, retained: retained, lastUsed: sequence, evicted: evicted)
        return Lease(id: id, worker: worker, reused: false, evicted: evicted)
    }
    mutating func evictionFinished(_ id: UUID) { slots[id]?.evicted = nil }
    /// Returns a worker to terminate. Keep its slot until termination completes.
    mutating func release(_ id: UUID, healthy: Bool) -> (any ProviderWorker)? {
        guard var slot = slots[id] else { return nil }
        if healthy && slot.retained && slot.worker.reusable && slot.worker.healthy {
            sequence += 1
            slot.busy = false
            slot.lastUsed = sequence
            slots[id] = slot
            return nil
        }
        slots[id]?.retiring = true
        return slot.worker
    }
    mutating func removed(_ id: UUID) { slots[id] = nil }
    var allWorkers: [(UUID, any ProviderWorker)] { slots.map { ($0.key, $0.value.worker) } }
    var idleWorkers: [(UUID, any ProviderWorker)] {
        slots.filter { !$0.value.busy && !$0.value.retiring }.map { ($0.key, $0.value.worker) }
    }
    var oldestIdle: (UUID, any ProviderWorker)? {
        slots.filter { !$0.value.busy && !$0.value.retiring }.min { $0.value.lastUsed < $1.value.lastUsed }
            .map { ($0.key, $0.value.worker) }
    }
    mutating func beginRetiring(_ id: UUID) { slots[id]?.retiring = true }
    var snapshot: WorkerPoolSnapshot {
        WorkerPoolSnapshot(
            retained: slots.values.filter { $0.retained && !$0.retiring }.count,
            idle: slots.values.filter { !$0.busy && !$0.retiring }.count,
            busy: slots.values.filter { $0.busy && !$0.retiring }.count,
            temporary: slots.values.filter { !$0.retained && !$0.retiring }.count,
            retiring: slots.values.filter { $0.retiring }.count,
            capacity: capacity, max_processes: maxProcesses,
            resident_memory_bytes: slots.values.reduce(0) { $0 + $1.worker.runner.residentMemoryBytes + ($1.evicted?.runner.residentMemoryBytes ?? 0) })
    }
}
