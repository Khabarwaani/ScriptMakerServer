import Foundation
import Testing

@testable import AgentCore

actor MockTracker {
    var active = 0
    var peak = 0
    func enter() {
        active += 1
        peak = max(peak, active)
    }
    func leave() { active -= 1 }
}

struct MockProvider: AIProvider {
    let id = "mock"
    var delayMilliseconds = 100
    var invalid = false
    var fail = false
    var tracker = MockTracker()
    func checkReadiness() async throws {}
    func execute(
        definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
        timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void
    ) async throws -> JSONValue {
        await tracker.enter()
        do {
            await onOutput(input["text"]?.string ?? "progress")
            try await Task.sleep(for: .milliseconds(delayMilliseconds))
            try Task.checkCancellation()
            if fail { throw AgentError("provider_execution_failed", "Mock provider failed.") }
            await tracker.leave()
            return .object(["result": invalid ? .number(1) : input["text"] ?? .string("ok")])
        } catch {
            await tracker.leave()
            throw error
        }
    }
}

func makeManager(
    _ fixture: AgentFixture, provider: MockProvider = MockProvider(), capacity: Int = 8, timeout: Int = 30,
    retention: Int = 3600, sessionLog: ExecutionSessionLog? = nil
) -> ExecutionManager {
    ExecutionManager(
        registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents), providers: ProviderCatalog(providers: [provider]),
        runtimeRoot: fixture.runtime,
        maxProcesses: capacity, timeoutSeconds: timeout, retentionSeconds: retention, sessionLog: sessionLog,
        resourceSample: {
            SystemResources(
                physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296, load_average: 0,
                cpu_count: 8)
        })
}
func request(_ text: String) -> ExecuteRequest {
    ExecuteRequest(agentID: "Echo", provider: "mock", input: .object(["text": .string(text)]))
}
func events(_ execution: AcceptedExecution) async -> [StreamEvent] {
    var values: [StreamEvent] = []
    for await event in execution.events { values.append(event) }
    return values
}
func waitForTerminal(_ manager: ExecutionManager, id: String) async throws -> ExecutionRecord {
    for _ in 0..<300 {
        let snapshot = await manager.snapshot()
        if let record = snapshot.records.first(where: {
            $0.execution_id == id && ["completed", "failed", "cancelled"].contains($0.status)
        }) {
            return record
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw AgentError("test_timeout", "Execution did not finish.")
}

@Test func successfulExecutionStreamsAndCleansUp() async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture)
    let accepted = try await manager.execute(request("first"))
    let stream = await events(accepted)
    #expect(stream.map(\.name) == ["started", "status", "output", "result", "completed"])
    #expect(stream.first(where: { $0.name == "result" })?.data["result"]?["result"] == .string("first"))
    let record = try await waitForTerminal(manager, id: accepted.id)
    #expect(record.status == "completed")
    #expect(record.running_at != nil && record.ended_at != nil && record.elapsed_seconds > 0)
    #expect(record.agent_id == nil && record.provider == nil && record.error == nil)
    #expect(stream.allSatisfy { $0.data["started_at"] != nil && $0.data["elapsed_seconds"] != nil })
    #expect(stream.last?.data["ended_at"] != nil)
    let later = await manager.snapshot().records.first { $0.execution_id == accepted.id }
    #expect(later?.elapsed_seconds == record.elapsed_seconds)
    #expect(!FileManager.default.fileExists(atPath: fixture.runtime.appendingPathComponent(accepted.id).path))
}

@Test(arguments: [true, false]) func failureNeverEmitsCompleted(schemaFailure: Bool) async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture, provider: MockProvider(invalid: schemaFailure, fail: !schemaFailure))
    let accepted = try await manager.execute(request("failed"))
    let stream = await events(accepted)
    #expect(stream.last?.name == "failed")
    #expect(!stream.contains(where: { $0.name == "completed" || $0.name == "result" }))
    let record = try await waitForTerminal(manager, id: accepted.id)
    #expect(record.status == "failed")
    #expect(record.error?.code == (schemaFailure ? "output_schema_validation_failed" : "provider_execution_failed"))
    #expect(record.error?.message == stream.last?.data["error"]?["message"]?.string)
    #expect(record.error?.execution_id == accepted.id)
    #expect(record.agent_id == nil && record.provider == nil && record.process_id == nil)
    #expect(stream.last?.data["error"]?["execution_id"] == .string(accepted.id))
}

@Test func concurrentBurstExceedsFiveWithoutMixingResults() async throws {
    let fixture = try AgentFixture()
    let tracker = MockTracker()
    let manager = makeManager(fixture, provider: MockProvider(delayMilliseconds: 300, tracker: tracker))
    var accepted: [AcceptedExecution] = []
    for index in 0..<12 { accepted.append(try await manager.execute(request("request-\(index)"))) }
    let initial = await manager.snapshot()
    #expect(initial.activeCount == 8 && initial.queuedCount == 4)
    for (index, execution) in accepted.enumerated() {
        let stream = await events(execution)
        #expect(
            stream.first(where: { $0.name == "result" })?.data["result"]?["result"]
                == .string("request-\(index)"))
        #expect(stream.allSatisfy { $0.data["execution_id"] == .string(execution.id) })
    }
    #expect(await tracker.peak == 8)
    #expect(await tracker.active == 0)
}

@Test func cancellationIsScopedAndIdempotent() async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture, provider: MockProvider(delayMilliseconds: 300))
    let first = try await manager.execute(request("cancel"))
    let second = try await manager.execute(request("keep"))
    _ = try await manager.cancel(first.id)
    _ = try await manager.cancel(first.id)
    #expect(await events(first).last?.name == "cancelled")
    #expect(await events(second).last?.name == "completed")
    #expect(try await manager.cancel(first.id).status == "cancelled")
    await #expect(throws: AgentError.self) { try await manager.cancel("unknown") }
}

@Test func disconnectDoesNotCancelAndTimeoutFails() async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture)
    let accepted = try await manager.execute(request("detached"), streaming: false)
    #expect(await manager.snapshot().records.first?.streaming == false)
    await manager.detach(accepted.id)
    #expect(try await waitForTerminal(manager, id: accepted.id).status == "completed")
    let timedManager = makeManager(fixture, provider: MockProvider(delayMilliseconds: 2000), timeout: 1)
    let timed = try await timedManager.execute(request("timeout"))
    #expect(await events(timed).last?.data["error"]?["code"] == .string("execution_timeout"))
    #expect(await timedManager.snapshot().records.first?.error?.code == "execution_timeout")
}

@Test func shutdownDrainsAndRejectsNewWork() async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture)
    let accepted = try await manager.execute(request("drain"))
    await manager.shutdown(timeoutSeconds: 2)
    #expect(await events(accepted).last?.name == "completed")
    #expect(await manager.snapshot().records.isEmpty)
    #expect(await manager.snapshot().queuedCount == 0)
    await #expect(throws: AgentError.self) { try await manager.execute(request("new")) }
}

@Test func resourcePressureDefersWorkAndQueuedCancellationCleansUp() async throws {
    let fixture = try AgentFixture()
    let manager = ExecutionManager(
        registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [MockProvider()]), runtimeRoot: fixture.runtime,
        resourceSample: {
            SystemResources(
                physical_memory_bytes: 8_589_934_592, available_memory_bytes: 0, load_average: 0, cpu_count: 8
            )
        })
    let accepted = try await manager.execute(request("deferred"))
    #expect(await manager.snapshot().queuedCount == 1)
    let queued = try #require(await manager.snapshot().records.first)
    #expect(queued.running_at == nil && queued.elapsed_seconds == 0)
    #expect(try await manager.cancel(accepted.id).status == "cancelled")
    #expect(await events(accepted).last?.name == "cancelled")
    #expect(await manager.snapshot().queuedCount == 0)
    let cancelled = try #require(await manager.snapshot().records.first)
    #expect(cancelled.running_at == nil && cancelled.elapsed_seconds == 0 && cancelled.ended_at != nil)
}

@Test func timingExcludesQueueTimeAndFreezesAtTermination() {
    let accepted = Date(timeIntervalSince1970: 1_000)
    var record = ExecutionRecord(
        execution_id: "exec_timing", agent_id: "Echo", version: "1.0.0", provider: "mock",
        status: "queued", streaming: true, started_at: accepted, resident_memory_bytes: 0)
    record.updateElapsed(at: accepted.addingTimeInterval(50))
    #expect(record.elapsed_seconds == 0)
    record.running_at = accepted.addingTimeInterval(60)
    record.status = "running"
    record.updateElapsed(at: accepted.addingTimeInterval(75))
    #expect(record.elapsed_seconds == 15)
    record.updateElapsed(at: accepted.addingTimeInterval(80))
    #expect(record.elapsed_seconds == 20)
    record.ended_at = accepted.addingTimeInterval(90)
    record.status = "completed"
    record.updateElapsed(at: accepted.addingTimeInterval(200))
    #expect(record.elapsed_seconds == 30)
}

@Test func completedRecordsRetainOnlyIDStateAndTiming() async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture)
    let execution = try await manager.execute(request("private input"))
    _ = await events(execution)
    // HTTP stream detachment after completion must not restore extra fields.
    await manager.detach(execution.id)
    let record = try await waitForTerminal(manager, id: execution.id)
    let json = try JSONValue.parse(String(decoding: JSONEncoder().encode(record), as: UTF8.self))
    #expect(Set(json.object!.keys) == Set([
        "execution_id", "status", "started_at", "running_at", "ended_at", "elapsed_seconds",
    ]))
    await manager.shutdown(timeoutSeconds: 0)
    #expect(await manager.snapshot().records.isEmpty)
    let restarted = makeManager(fixture)
    #expect(await restarted.snapshot().records.isEmpty)
}

@Test func shutdownCancelsActiveAndQueuedWorkBeforePurging() async throws {
    let fixture = try AgentFixture()
    let tracker = MockTracker()
    let manager = makeManager(
        fixture, provider: MockProvider(delayMilliseconds: 10_000, tracker: tracker), capacity: 1)
    let running = try await manager.execute(request("running"))
    let queued = try await manager.execute(request("queued"))
    await manager.shutdown(timeoutSeconds: 0)
    #expect(await events(running).last?.name == "cancelled")
    #expect(await events(queued).last?.name == "cancelled")
    let snapshot = await manager.snapshot()
    #expect(snapshot.records.isEmpty && snapshot.activeCount == 0 && snapshot.queuedCount == 0)
    #expect(await tracker.active == 0)
}
