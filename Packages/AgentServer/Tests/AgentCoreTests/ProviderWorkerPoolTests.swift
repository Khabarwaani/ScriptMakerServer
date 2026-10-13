import Foundation
import Testing

@testable import AgentCore

final class SyntheticWorker: ProviderWorker, @unchecked Sendable {
    let runner = ProcessRunner()
    let reusable: Bool
    private let lock = NSLock()
    private var closed = false
    private var active = false
    private var resetFails = false
    private var marker: String?
    private var stopCount = 0
    var stops: Int { lock.withLock { stopCount } }
    let delay: Int
    init(reusable: Bool = true, delay: Int = 50) { self.reusable = reusable; self.delay = delay }
    var healthy: Bool { lock.withLock { !closed } }
    func execute(
        definition: AgentDefinition, input: JSONValue, directory: URL, timeoutSeconds: Int,
        onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void,
        onPhase: @escaping @Sendable (String, Double) async -> Void
    ) async throws -> JSONValue {
        try lock.withLock {
            guard !active, marker == nil, !closed else { throw AgentError("context_leak", "Worker context was reused concurrently or without reset.") }
            active = true
            marker = input["text"]?.string
            resetFails = marker == "reset-fail"
        }
        defer { lock.withLock { active = false } }
        try await Task.sleep(for: .milliseconds(delay))
        await onPhase("provider_startup_seconds", 0.001)
        await onPhase("generation_seconds", Double(delay) / 1000)
        if input["text"] == .string("fail") { throw AgentError("provider_execution_failed", "Synthetic failure.") }
        return .object(["result": input["text"] == .string("invalid") ? .number(1) : input["text"] ?? .string("ok")])
    }
    func reset() async throws {
        try lock.withLock {
            if resetFails { throw AgentError("worker_reset_failed", "Synthetic reset failure.") }
            marker = nil
        }
    }
    func shutdown() async { lock.withLock { if !closed { stopCount += 1 }; closed = true; marker = nil } }
}

final class WorkerFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SyntheticWorker] = []
    let delay: Int
    init(delay: Int = 50) { self.delay = delay }
    var workers: [SyntheticWorker] { lock.withLock { storage } }
    func make() -> SyntheticWorker {
        lock.withLock { let worker = SyntheticWorker(delay: delay); storage.append(worker); return worker }
    }
}

struct PooledTestProvider: AIProvider {
    let id = "mock"
    let factory: WorkerFactory
    func checkReadiness() async throws {}
    func makeWorker(ownership: WorkerOwnershipStore?) throws -> any ProviderWorker { factory.make() }
    func execute(definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
                 timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
                 onProgress: @escaping @Sendable (JSONValue) async -> Void) async throws -> JSONValue {
        throw AgentError("test_error", "Expected worker execution.")
    }
}

private final class MemoryPressure: @unchecked Sendable {
    private let lock = NSLock()
    private var low = false
    func set(_ value: Bool) { lock.withLock { low = value } }
    func sample() -> SystemResources {
        lock.withLock {
            SystemResources(physical_memory_bytes: 8_589_934_592,
                available_memory_bytes: low ? 0 : 4_294_967_296, load_average: 0, cpu_count: 8)
        }
    }
}

@Test func memoryPressureReclaimsIdleWorkersWithoutRunningQueuedWork() async throws {
    let fixture = try AgentFixture(), factory = WorkerFactory(), pressure = MemoryPressure()
    let manager = ExecutionManager(registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [PooledTestProvider(factory: factory)]), runtimeRoot: fixture.runtime,
        providerPoolSize: 1, resourceSample: pressure.sample)
    _ = await events(try await manager.execute(request("first")))
    pressure.set(true)
    let second = try await manager.execute(request("second"))
    for _ in 0..<200 {
        if factory.workers.first?.healthy == false { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    let blocked = await manager.snapshot()
    #expect(blocked.activeCount == 0 && blocked.queuedCount == 1)
    #expect(blocked.records.first(where: { $0.execution_id == second.id })?.queue_reasons == ["available_memory"])
    #expect(factory.workers.count == 1 && factory.workers.first?.healthy == false)
    pressure.set(false)
    await manager.maintenance()
    #expect(await events(second).last?.name == "completed")
    #expect(factory.workers.count == 2)
    await manager.shutdown(timeoutSeconds: 1)
}

func pooledManager(_ fixture: AgentFixture, factory: WorkerFactory, size: Int = 2, max: Int = 3, timeout: Int = 1800) -> ExecutionManager {
    ExecutionManager(registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [PooledTestProvider(factory: factory)]), runtimeRoot: fixture.runtime,
        maxProcesses: max, timeoutSeconds: timeout, providerPoolSize: size, resourceSample: {
            SystemResources(physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296,
                            load_average: 0, cpu_count: 8)
        })
}

@Test(arguments: [false, true])
func cancellationAndTimeoutRetirePooledWorkers(timeout: Bool) async throws {
    let fixture = try AgentFixture(), factory = WorkerFactory(delay: 2000)
    let manager = pooledManager(fixture, factory: factory, timeout: timeout ? 1 : 1800)
    let accepted = try await manager.execute(request("slow"))
    if !timeout {
        try await Task.sleep(for: .milliseconds(50))
        _ = try await manager.cancel(accepted.id)
    }
    let stream = await events(accepted)
    #expect(stream.last?.name == (timeout ? "failed" : "cancelled"))
    if timeout { #expect(stream.last?.data["error"]?["code"] == .string("execution_timeout")) }
    #expect(!stream.contains { $0.name == "result" || $0.name == "completed" })
    #expect(factory.workers.count == 1 && factory.workers.first?.healthy == false)
    #expect(await manager.snapshot().worker_pool?.retained == 0)
    await manager.shutdown(timeoutSeconds: 1)
}

@Test func globalPoolReusesWorkersAndEvictsOnlyIdleLRU() throws {
    var pool = ProviderWorkerPool(capacity: 2, maxProcesses: 3)
    let a = ProviderWorkerPool.Key(provider: "codex", agent: "NewsResearcher", version: "1.1.0")
    let b = ProviderWorkerPool.Key(provider: "grok", agent: "ScriptRefiner", version: "1.1.0")
    let c = ProviderWorkerPool.Key(provider: "codex", agent: "ScriptRefiner", version: "1.0.0")
    let first = try #require(pool.acquire(key: a) { SyntheticWorker() })
    #expect(pool.release(first.id, healthy: true) == nil)
    let second = try #require(pool.acquire(key: b) { SyntheticWorker() })
    #expect(pool.release(second.id, healthy: true) == nil)
    let reused = try #require(pool.acquire(key: a) { Issue.record("Reuse must not allocate a worker"); return SyntheticWorker() })
    #expect(reused.reused && reused.id == first.id)
    #expect(pool.release(reused.id, healthy: true) == nil)
    let third = try #require(pool.acquire(key: c) { SyntheticWorker() })
    #expect(third.evicted === second.worker)
    #expect(pool.snapshot.retained == 2 && pool.snapshot.idle == 1)
}

@Test func busyPoolUsesBoundedTemporaryWorkersAndKeepsRetiringSlots() throws {
    var pool = ProviderWorkerPool(capacity: 1, maxProcesses: 2)
    let key = ProviderWorkerPool.Key(provider: "mock", agent: "Echo", version: "1.0.0")
    let first = try #require(pool.acquire(key: key) { SyntheticWorker() })
    let burst = try #require(pool.acquire(key: key) { SyntheticWorker() })
    #expect(burst.evicted == nil && pool.snapshot.temporary == 1)
    #expect(try pool.acquire(key: key) { Issue.record("Full pool must not allocate"); return SyntheticWorker() } == nil)
    #expect(pool.release(burst.id, healthy: true) === burst.worker)
    #expect(pool.snapshot.retiring == 1)
    #expect(try pool.acquire(key: key) { SyntheticWorker() } == nil)
    pool.removed(burst.id)
    #expect(pool.release(first.id, healthy: false) === first.worker)
    #expect(pool.snapshot.retained == 0 && pool.snapshot.retiring == 1)
}

@Test func pooledRequestsResetContextsAndShutdownRetainedWorkers() async throws {
    let fixture = try AgentFixture(), factory = WorkerFactory()
    let manager = pooledManager(fixture, factory: factory)
    let first = try await manager.execute(request("private-first"))
    _ = await events(first)
    let second = try await manager.execute(request("second"))
    let output = await events(second)
    #expect(output.first(where: { $0.name == "result" })?.data["result"]?["result"] == .string("second"))
    #expect(factory.workers.count == 1)
    let snapshot = await manager.snapshot()
    #expect(snapshot.worker_pool?.idle == 1 && snapshot.worker_pool?.retained == 1)
    let record = try #require(snapshot.records.first(where: { $0.execution_id == second.id }))
    #expect(record.worker_reused == true)
    #expect(record.phase_timings?["total_seconds"] ?? 0 > 0)
    await manager.shutdown(timeoutSeconds: 1)
    #expect(factory.workers.allSatisfy { !$0.healthy && $0.stops == 1 })
    #expect(await manager.snapshot().worker_pool?.retained == 0)
}

@Test(arguments: ["fail", "invalid", "reset-fail"])
func workerErrorsRetireWithoutPublishingSuccess(value: String) async throws {
    let fixture = try AgentFixture(), factory = WorkerFactory()
    let manager = pooledManager(fixture, factory: factory)
    let failed = try await manager.execute(request(value))
    let stream = await events(failed)
    #expect(stream.last?.name == "failed" && !stream.contains { $0.name == "result" || $0.name == "completed" })
    #expect(factory.workers.first?.healthy == false)
    let next = try await manager.execute(request("valid"))
    _ = await events(next)
    #expect(factory.workers.count == 2)
    await manager.shutdown(timeoutSeconds: 1)
}

@Test func queuedRequestsRecordCapacityReasonAndBurstWorkersAreClosed() async throws {
    let fixture = try AgentFixture(), factory = WorkerFactory(delay: 120)
    let manager = pooledManager(fixture, factory: factory, size: 1, max: 2)
    var accepted: [AcceptedExecution] = []
    for index in 0..<3 { accepted.append(try await manager.execute(request("\(index)"))) }
    let queued = await manager.snapshot()
    #expect(queued.queuedCount == 1 && queued.worker_pool?.temporary == 1)
    #expect(queued.records.last?.queue_reasons == ["process_limit"])
    for item in accepted { _ = await events(item) }
    let finished = await manager.snapshot()
    #expect(finished.worker_pool?.retained == 1 && finished.worker_pool?.temporary == 0)
    #expect(finished.records.allSatisfy { ($0.phase_timings?["queue_seconds"] ?? -1) >= 0 })
    await manager.shutdown(timeoutSeconds: 1)
    #expect(factory.workers.allSatisfy { !$0.healthy })
}
