import Foundation

public actor ExecutionManager {
    private struct Work: Sendable {
        let definition: AgentDefinition
        let input: JSONValue
        let provider: any AIProvider
    }
    private struct Entry: Sendable {
        var record: ExecutionRecord
        var continuation: AsyncStream<StreamEvent>.Continuation?
        let runner: ProcessRunner
        var task: Task<Void, Never>?
        var timer: Task<Void, Never>?
        var timedOut = false
    }
    private let registry: AgentRegistry
    private let providers: ProviderCatalog
    private let runtimeRoot: URL
    private let maxProcesses: Int
    private let maxQueued: Int
    private let timeoutSeconds: Int
    private let retentionSeconds: Int
    private let resourceSample: @Sendable () -> SystemResources
    private var entries: [String: Entry] = [:]
    private var pending: [String: Work] = [:]
    private var queue: [String] = []
    private var accepting = true
    private var lastHeartbeat = Date.distantPast

    public init(
        registry: AgentRegistry, providers: ProviderCatalog, runtimeRoot: URL,
        maxProcesses: Int = 8, maxQueued: Int = 64, timeoutSeconds: Int = 1800, retentionSeconds: Int = 3600,
        resourceSample: @escaping @Sendable () -> SystemResources = { SystemResources.sample() }
    ) {
        self.registry = registry
        self.providers = providers
        self.runtimeRoot = runtimeRoot
        self.maxProcesses = maxProcesses
        self.maxQueued = maxQueued
        self.timeoutSeconds = timeoutSeconds
        self.retentionSeconds = retentionSeconds
        self.resourceSample = resourceSample
    }

    public func execute(_ request: ExecuteRequest) async throws -> AcceptedExecution {
        guard accepting else {
            throw AgentError(
                "server_shutting_down", "The server is shutting down and cannot accept new executions.")
        }
        guard request.input.object != nil, !request.provider.isEmpty else {
            throw AgentError("invalid_request", "Input must be a JSON object and provider must be specified.")
        }
        let definition = try await registry.resolve(id: request.agent_id, version: request.version)
        if let schema = definition.inputSchema {
            do { try OutputValidator.validate(request.input, schema: schema) } catch {
                throw AgentError(
                    "input_schema_validation_failed", "Input does not match the selected agent input schema.")
            }
        }
        let provider = try await providers.resolve(request.provider)
        guard accepting else { throw AgentError("server_shutting_down", "The server is shutting down.") }
        prune()
        guard queue.count < maxQueued, entries.count < 10000 else {
            throw AgentError(
                "resource_pressure", "The execution queue or retained status capacity is full. Retry later.")
        }
        let id = "exec_" + UUID().uuidString.lowercased()
        let (stream, continuation) = AsyncStream<StreamEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128))
        let record = ExecutionRecord(
            execution_id: id, agent_id: definition.id, version: definition.version,
            provider: provider.id, status: "queued", streaming: true, started_at: Date(),
            resident_memory_bytes: 0)
        entries[id] = Entry(record: record, continuation: continuation, runner: ProcessRunner())
        pending[id] = Work(definition: definition, input: request.input, provider: provider)
        queue.append(id)
        emit(
            id, "started",
            [
                "agent_id": .string(definition.id), "version": .string(definition.version),
                "provider": .string(provider.id), "status": .string("queued"),
            ])
        pump()
        return AcceptedExecution(id: id, events: stream)
    }

    public func detach(_ id: String) {
        entries[id]?.record.streaming = false
        entries[id]?.continuation?.finish()
        entries[id]?.continuation = nil
    }

    public func cancel(_ id: String) throws -> ExecutionRecord {
        guard let entry = entries[id] else {
            throw AgentError("unknown_execution", "The execution does not exist.")
        }
        if terminal(entry.record.status) || entry.record.status == "cancelling" { return entry.record }
        if entry.record.status == "queued" {
            pending[id] = nil
            queue.removeAll { $0 == id }
            finish(id, state: "cancelled", event: "cancelled")
        } else {
            entries[id]?.record.status = "cancelling"
            emit(id, "status", ["status": .string("cancelling")])
            entry.runner.cancel()
            entry.task?.cancel()
        }
        return entries[id]!.record
    }

    public func snapshot() -> ExecutionSnapshot {
        prune()
        pump()
        let records = entries.values.map { entry in
            var record = entry.record
            record.process_id = entry.runner.processID
            record.resident_memory_bytes = entry.runner.residentMemoryBytes
            return record
        }.sorted { $0.started_at < $1.started_at }
        return ExecutionSnapshot(
            records: records,
            activeCount: records.filter { ["running", "cancelling"].contains($0.status) }.count,
            queuedCount: queue.count,
            residentMemoryBytes: records.reduce(0) { $0 + $1.resident_memory_bytes }, accepting: accepting)
    }

    public func maintenance() {
        prune()
        pump()
        if Date().timeIntervalSince(lastHeartbeat) >= 10 {
            lastHeartbeat = Date()
            for (id, entry) in entries where !terminal(entry.record.status) {
                emit(id, "status", ["status": .string(entry.record.status)])
            }
        }
    }

    /// Reject new work, allow accepted jobs to drain, then cancel overdue work.
    public func shutdown(timeoutSeconds: Int) async {
        accepting = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while entries.values.contains(where: { !terminal($0.record.status) })
            && ContinuousClock.now < deadline && !Task.isCancelled
        {
            pump()
            try? await Task.sleep(for: .milliseconds(100))
        }
        for id in Array(entries.keys) where entries[id].map({ !terminal($0.record.status) }) == true {
            _ = try? cancel(id)
        }
        while entries.values.contains(where: { !terminal($0.record.status) }) {
            // A cancelled shutdown task must still reap its provider processes.
            await Task.detached { try? await Task.sleep(for: .milliseconds(50)) }.value
        }
    }

    private func terminal(_ state: String) -> Bool { ["completed", "failed", "cancelled"].contains(state) }
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(retentionSeconds))
        entries = entries.filter { _, value in !(value.record.ended_at.map { $0 < cutoff } ?? false) }
    }
    private func pump() {
        let active = entries.values.filter { $0.task != nil }.count
        let memory = entries.values.reduce(UInt64(0)) { $0 + $1.runner.residentMemoryBytes }
        let resources = resourceSample()
        guard memory < resources.physical_memory_bytes * 65 / 100 else { return }
        if let available = resources.available_memory_bytes,
            available < max(256 * 1_048_576, resources.physical_memory_bytes / 20)
        {
            return
        }
        if let load = resources.load_average, load > Double(resources.cpu_count * 2) { return }
        for _ in 0..<max(0, maxProcesses - active) {
            guard !queue.isEmpty else { break }
            let id = queue.removeFirst()
            guard let work = pending.removeValue(forKey: id), let runner = entries[id]?.runner else {
                continue
            }
            entries[id]?.record.status = "running"
            emit(id, "status", ["status": .string("running")])
            entries[id]?.task = Task { await self.perform(id, work: work, runner: runner) }
            entries[id]?.timer = Task {
                do { try await Task.sleep(for: .seconds(self.timeoutSeconds)) } catch { return }
                self.timeout(id)
            }
        }
    }
    private func timeout(_ id: String) {
        guard let entry = entries[id], !terminal(entry.record.status) else { return }
        entries[id]?.timedOut = true
        _ = try? cancel(id)
    }
    private func perform(_ id: String, work: Work, runner: ProcessRunner) async {
        let directory = runtimeRoot.appendingPathComponent(id, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let result = try await work.provider.execute(
                definition: work.definition, input: work.input, runner: runner, directory: directory,
                timeoutSeconds: timeoutSeconds,
                onOutput: { text in await self.providerOutput(id, text: text) },
                onProgress: { progress in await self.providerProgress(id, progress: progress) })
            guard entries[id]?.record.status != "cancelling" else { throw CancellationError() }
            try OutputValidator.validate(result, schema: work.definition.outputSchema)
            entries[id]?.record.schema_validated = true
            emit(id, "result", ["result": result])
            finish(id, state: "completed", event: "completed")
        } catch {
            if entries[id]?.timedOut == true {
                finish(
                    id, state: "failed", event: "failed",
                    error: AgentError("execution_timeout", "Execution exceeded its configured timeout."))
            } else if entries[id]?.record.status == "cancelling" || error is CancellationError {
                finish(id, state: "cancelled", event: "cancelled")
            } else {
                let failure =
                    error as? AgentError ?? AgentError("internal_error", "Execution could not complete.")
                if failure.code == "output_schema_validation_failed" {
                    entries[id]?.record.schema_validated = false
                }
                finish(id, state: "failed", event: "failed", error: failure)
            }
        }
    }
    private func providerOutput(_ id: String, text: String) {
        guard entries[id]?.record.status == "running" else { return }
        emit(id, "output", ["text": .string(text)])
    }
    private func providerProgress(_ id: String, progress: JSONValue) {
        guard entries[id]?.record.status == "running" else { return }
        emit(id, "status", ["status": .string("running"), "progress": progress])
    }
    private func emit(_ id: String, _ name: String, _ fields: [String: JSONValue] = [:]) {
        guard let continuation = entries[id]?.continuation else { return }
        var data = fields
        data["execution_id"] = .string(id)
        switch continuation.yield(StreamEvent(name: name, data: .object(data))) {
        case .dropped, .terminated: detach(id)
        default: break
        }
    }
    private func finish(_ id: String, state: String, event: String, error: AgentError? = nil) {
        var failure = error
        failure?.execution_id = id
        entries[id]?.record.status = state
        entries[id]?.record.ended_at = Date()
        entries[id]?.record.error = failure
        if let failure, let data = try? JSONEncoder().encode(failure),
            let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        {
            emit(id, event, ["error": json])
        } else {
            emit(id, event, ["status": .string(state)])
        }
        entries[id]?.continuation?.finish()
        entries[id]?.continuation = nil
        entries[id]?.record.streaming = false
        entries[id]?.timer?.cancel()
        entries[id]?.timer = nil
        entries[id]?.task = nil
        print("execution=\(id) state=\(state) code=\(failure?.code ?? "none")")
        pump()
    }
}
