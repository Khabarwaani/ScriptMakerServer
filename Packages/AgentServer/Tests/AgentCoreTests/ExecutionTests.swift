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
    retention: Int = 3600
) -> ExecutionManager {
    ExecutionManager(
        registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents), providers: ProviderCatalog(providers: [provider]),
        runtimeRoot: fixture.runtime,
        maxProcesses: capacity, timeoutSeconds: timeout, retentionSeconds: retention,
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
    #expect(record.status == "completed" && record.schema_validated == true)
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
    #expect(record.error?.execution_id == accepted.id)
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
    let accepted = try await manager.execute(request("detached"))
    await manager.detach(accepted.id)
    #expect(try await waitForTerminal(manager, id: accepted.id).status == "completed")
    let timedManager = makeManager(fixture, provider: MockProvider(delayMilliseconds: 2000), timeout: 1)
    let timed = try await timedManager.execute(request("timeout"))
    #expect(await events(timed).last?.data["error"]?["code"] == .string("execution_timeout"))
}

@Test func shutdownDrainsAndRejectsNewWork() async throws {
    let fixture = try AgentFixture()
    let manager = makeManager(fixture)
    let accepted = try await manager.execute(request("drain"))
    await manager.shutdown(timeoutSeconds: 2)
    #expect(await events(accepted).last?.name == "completed")
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
    #expect(try await manager.cancel(accepted.id).status == "cancelled")
    #expect(await events(accepted).last?.name == "cancelled")
    #expect(await manager.snapshot().queuedCount == 0)
}
