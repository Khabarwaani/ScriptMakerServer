import Foundation
import Testing
import ShekharJokeGenerator

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

@Test func completedRecordsRetainOnlyCompactOperationalDiagnostics() async throws {
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
        "phase_timings", "worker_reused",
    ]))
    #expect(!(try json.text()).contains("private input"))
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

private struct DefaultedInputPackage: AgentPackageContract {
    static let id = "DefaultedAgent"
    static let versions = ["1.0.0"]
    static func directory(version: String) throws -> URL { URL(fileURLWithPath: "/tmp/DefaultedAgent/1.0.0") }
    static func role(version: String) throws -> String { "Role statement." }
    static func instructions(version: String) throws -> String { "Instructions." }
    static func outputSchema(version: String) throws -> String {
        #"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["result"],"properties":{"result":{"type":"string"}}}"#
    }
    static func inputSchema(version: String) throws -> String? {
        #"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["text"],"properties":{"text":{"type":"string"},"count":{"type":"integer","default":5}}}"#
    }
}

@Test func executionManagerPopulatesSchemaDefaultsBeforeProviderExecution() async throws {
    let fixture = try AgentFixture()
    actor InputCapture {
        var captured: JSONValue?
        func record(_ value: JSONValue) { captured = value }
    }
    let capture = InputCapture()
    struct CapturingProvider: AIProvider {
        let id = "capture"
        let capture: InputCapture
        func checkReadiness() async throws {}
        func execute(
            definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
            timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
            onProgress: @escaping @Sendable (JSONValue) async -> Void
        ) async throws -> JSONValue {
            await capture.record(input)
            return .object(["result": .string("done")])
        }
    }
    let manager = ExecutionManager(
        registry: AgentRegistry(packages: [DefaultedInputPackage.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [CapturingProvider(capture: capture)]),
        runtimeRoot: fixture.runtime,
        maxProcesses: 2, timeoutSeconds: 30, retentionSeconds: 3600,
        resourceSample: { SystemResources(physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296, load_average: 0, cpu_count: 8) }
    )
    let execution = try await manager.execute(
        ExecuteRequest(agentID: "DefaultedAgent", provider: "capture", input: .object(["text": .string("hello")])),
        streaming: false
    )
    for await _ in execution.events {}
    let captured = await capture.captured
    #expect(captured?["text"] == .string("hello"))
    #expect(captured?["count"] == .number(5))
}

@Test(arguments: ["legacy", "native", "failed"]) func testShekharJokeGeneratorExecutesViaTerminalAgentSessionInCLIProvider(transport: String) async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shekhar_tas_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let scriptURL = tempDir.appendingPathComponent("mock_agy.sh")
    let result: JSONValue = .object(["items": .array([.object([
        "title": .string("ताज़ा खबर"), "date": .string("16-10-2026"),
        "link": .string("https://news.in/story"), "category": .string("Trending"),
        "joke1": .string("छोटा मज़ाक"), "joke2": .string("बड़ा मज़ाक"),
        "script": .string("#1\ntitle: ताज़ा खबर")
    ])])])
    let final: JSONValue = transport == "legacy"
        ? .object(["type": .string("result"), "response": .string(try result.text())])
        : .object(["event": .string("result"), "result": .object([
            "status": .string(transport == "failed" ? "FAILED" : "SUCCESS"),
            "response": .string("Done"), "structured_output": result
        ])])
    let invocations = tempDir.appendingPathComponent("invocations.txt")
    let script = """
    #!/bin/bash
    [[ "$1" == "--help" ]] && exit 0
    arguments=("$@")
    count=${#arguments[@]}
    [[ "${arguments[$((count - 2))]}" == "--print" ]] || { echo 'Print must precede the prompt' >&2; exit 2; }
    [[ "${arguments[$((count - 1))]}" == *"Input:"* ]] || { echo 'Missing prompt' >&2; exit 2; }
    printf 'run\\n' >> '\(invocations.path)'
    echo '{"event":"init"}'
    echo '{"event":"step_update","step_update":{"text_delta":"Working"}}'
    echo '\(try final.text())'
    """
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fixture = try AgentFixture()
    let provider = CLIProvider(kind: .antigravity, settings: .init(executable: scriptURL.path))
    let manager = ExecutionManager(
        registry: AgentRegistry(packages: [ShekharJokeGeneratorDefinition.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [provider]),
        runtimeRoot: fixture.runtime,
        maxProcesses: 2, timeoutSeconds: 30, retentionSeconds: 3600,
        resourceSample: { SystemResources(physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296, load_average: 0, cpu_count: 8) }
    )

    let input: JSONValue = .object([
        "output_count": .number(1),
        "news_count": .number(3),
        "jokes_per_category": .number(2)
    ])

    let execution = try await manager.execute(
        ExecuteRequest(agentID: "ShekharJokeGenerator", provider: "antigravity", input: input),
        streaming: true
    )

    var streamedTexts: [String] = []
    var finalResult: JSONValue?
    for await event in execution.events {
        if event.name == "output", let text = event.data["text"]?.string {
            streamedTexts.append(text)
        }
        if event.name == "result", let res = event.data["result"] {
            finalResult = res
        }
    }

    let snapshot = await manager.snapshot()
    guard let record = snapshot.records.first(where: { $0.execution_id == execution.id }) else {
        Issue.record("Missing execution record")
        return
    }

    let runs = try String(contentsOf: invocations, encoding: .utf8).split(whereSeparator: \.isNewline)
    #expect(runs.count == 1)
    if transport == "failed" {
        #expect(record.status == "failed")
        #expect(record.error?.code == "provider_execution_failed")
        #expect(finalResult == nil)
    } else {
        #expect(record.status == "completed")
        #expect(record.error == nil)
        #expect(finalResult?["items"]?.array?.count == 1)
        #expect(finalResult?["items"]?.array?[0]["title"]?.string == "ताज़ा खबर")
        #expect(finalResult?["items"]?.array?[0]["joke1"]?.string == "छोटा मज़ाक")
    }
}


@Test func cpuPressureQueueFailsWithinItsDeadlineWithoutLaunchingProvider() async throws {
    let fixture = try AgentFixture()
    let provider = MockProvider()
    let manager = ExecutionManager(
        registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [provider]), runtimeRoot: fixture.runtime,
        queueTimeoutSeconds: 1,
        resourceSample: { SystemResources(
            physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296,
            load_average: 99, cpu_count: 8) })
    let execution = try await manager.execute(request("blocked"))
    let stream = await events(execution)
    let snapshot = await manager.snapshot()
    let record = try #require(snapshot.records.first)
    #expect(record.status == "failed")
    #expect(record.error?.code == "queue_timeout")
    #expect(record.error?.httpStatus == 503)
    #expect(record.running_at == nil)
    #expect(record.queue_reasons == ["cpu_load"])
    #expect((record.phase_timings?["queue_seconds"] ?? 0) >= 1)
    #expect(snapshot.queuedCount == 0 && snapshot.activeCount == 0)
    #expect(await provider.tracker.peak == 0)
    #expect(stream.last?.name == "failed")
}

@Test func queueDeadlineDoesNotCancelAnExecutionThatAlreadyStarted() async throws {
    let fixture = try AgentFixture()
    let provider = MockProvider(delayMilliseconds: 1200)
    let manager = ExecutionManager(
        registry: AgentRegistry(packages: [EchoPackage.self], root: fixture.agents),
        providers: ProviderCatalog(providers: [provider]), runtimeRoot: fixture.runtime,
        queueTimeoutSeconds: 1,
        resourceSample: { SystemResources(
            physical_memory_bytes: 8_589_934_592, available_memory_bytes: 4_294_967_296,
            load_average: 0, cpu_count: 8) })
    let execution = try await manager.execute(request("started"))
    #expect(await events(execution).last?.name == "completed")
    #expect(await manager.snapshot().records.first?.error == nil)
}
