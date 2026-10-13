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
        var runner: ProcessRunner?
        var task: Task<Void, Never>?
        var timer: Task<Void, Never>?
        var timedOut = false
        var lease: ProviderWorkerPool.Lease?
        var requestBegan = Date()
    }
    private let registry: AgentRegistry
    private let providers: ProviderCatalog
    private let runtimeRoot: URL
    private let sessionLog: ExecutionSessionLog?
    private let ownership: WorkerOwnershipStore?
    private var pool: ProviderWorkerPool
    private var pumping = false
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
        sessionLog: ExecutionSessionLog? = nil,
        providerPoolSize: Int = 5, ownership: WorkerOwnershipStore? = nil,
        resourceSample: @escaping @Sendable () -> SystemResources = { SystemResources.sample() }
    ) {
        self.registry = registry
        self.providers = providers
        self.runtimeRoot = runtimeRoot
        self.sessionLog = sessionLog
        self.ownership = ownership
        self.pool = ProviderWorkerPool(capacity: providerPoolSize, maxProcesses: maxProcesses)
        self.maxProcesses = maxProcesses
        self.maxQueued = maxQueued
        self.timeoutSeconds = timeoutSeconds
        self.retentionSeconds = retentionSeconds
        self.resourceSample = resourceSample
    }

    public func execute(_ request: ExecuteRequest, streaming: Bool = true) async throws -> AcceptedExecution {
        let requestBegan = Date()
        guard accepting else {
            throw AgentError(
                "server_shutting_down", "The server is shutting down and cannot accept new executions.")
        }
        guard request.input.object != nil, !request.provider.isEmpty else {
            throw AgentError("invalid_request", "Input must be a JSON object and provider must be specified.")
        }
        let definition = try await registry.resolve(id: request.agent_id, version: request.version)
        var effectiveInput = request.input
        if let schema = definition.inputSchema {
            effectiveInput = try InputValidator.prepare(
                effectiveInput, schema: schema, agentID: definition.id, version: definition.version)
        }
        let readinessBegan = Date()
        let provider = try await providers.resolve(request.provider)
        let readinessDuration = Date().timeIntervalSince(readinessBegan)
        guard accepting else { throw AgentError("server_shutting_down", "The server is shutting down.") }
        prune()
        guard queue.count < maxQueued, entries.count < 10000 else {
            throw AgentError(
                "resource_pressure", "The execution queue or retained status capacity is full. Retry later.")
        }
        let id = "exec_" + UUID().uuidString.lowercased()
        let (stream, continuation) = AsyncStream<StreamEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128))
        var record = ExecutionRecord(
            execution_id: id, agent_id: definition.id, version: definition.version,
            provider: provider.id, status: "queued", streaming: streaming, started_at: Date(),
            resident_memory_bytes: 0)
        record.phase_timings = [
            "readiness_seconds": readinessDuration,
            "preparation_seconds": max(0, Date().timeIntervalSince(requestBegan) - readinessDuration),
        ]
        entries[id] = Entry(record: record, continuation: continuation, requestBegan: requestBegan)
        pending[id] = Work(definition: definition, input: effectiveInput, provider: provider)
        queue.append(id)
        logState(id)
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
        if let state = entries[id]?.record.status, !terminal(state) {
            entries[id]?.record.streaming = false
        }
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
            logState(id)
            emit(id, "status", ["status": .string("cancelling")])
            (entry.lease?.worker.runner ?? entry.runner)?.cancel()
            entry.task?.cancel()
        }
        return entries[id]!.record
    }

    public func snapshot() -> ExecutionSnapshot {
        prune()
        pump()
        let records = entries.values.map { entry in
            var record = entry.record
            record.updateElapsed()
            if let runner = entry.lease?.worker.runner ?? entry.runner {
                record.process_id = runner.processID
                record.resident_memory_bytes = runner.residentMemoryBytes
            }
            return record
        }.sorted { $0.started_at < $1.started_at }
        return ExecutionSnapshot(
            records: records,
            activeCount: records.filter { ["running", "cancelling"].contains($0.status) }.count,
            queuedCount: queue.count,
            residentMemoryBytes: pool.snapshot.resident_memory_bytes, accepting: accepting,
            worker_pool: pool.snapshot)
    }

    public func recentExecutionLogs() throws -> [ExecutionRecord] {
        guard let sessionLog else { throw AgentError("execution_log_unavailable", "Session execution logging is unavailable.") }
        return try sessionLog.recentRecords()
    }

    public func executionLogFile() throws -> (url: URL, length: UInt64) {
        guard let sessionLog else { throw AgentError("execution_log_unavailable", "Session execution logging is unavailable.") }
        return try sessionLog.snapshotFile()
    }

    private func logState(_ id: String) {
        guard var record = entries[id]?.record else { return }
        record.updateElapsed()
        sessionLog?.append(record)
    }

    public func maintenance() {
        reapIdleWorkers()
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
        entries.removeAll()
        pending.removeAll()
        queue.removeAll()
        for (id, worker) in pool.allWorkers {
            pool.beginRetiring(id)
            await worker.shutdown()
            pool.removed(id)
        }
    }

    private func terminal(_ state: String) -> Bool { ["completed", "failed", "cancelled"].contains(state) }
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(retentionSeconds))
        entries = entries.filter { _, value in !(value.record.ended_at.map { $0 < cutoff } ?? false) }
    }
    private func pump() {
        reapIdleWorkers()
        guard !pumping, !queue.isEmpty else { return }
        pumping = true
        defer { pumping = false }
        let memory = pool.snapshot.resident_memory_bytes
        let resources = resourceSample()
        guard memory < resources.physical_memory_bytes * 65 / 100 else { queueBlocked("provider_memory"); return }
        if let available = resources.available_memory_bytes,
            available < max(256 * 1_048_576, resources.physical_memory_bytes / 20)
        {
            queueBlocked("available_memory")
            return
        }
        if let load = resources.load_average, load > Double(resources.cpu_count * 2) { queueBlocked("cpu_load"); return }
        for _ in 0..<maxProcesses {
            guard let id = queue.first, let work = pending[id] else { break }
            let lease: ProviderWorkerPool.Lease
            do {
                guard let acquired = try pool.acquire(
                    key: .init(provider: work.provider.id, agent: work.definition.id, version: work.definition.version),
                    make: { try work.provider.makeWorker(ownership: ownership) })
                else { queueBlocked("process_limit"); break }
                lease = acquired
            } catch {
                queue.removeFirst()
                pending[id] = nil
                finish(id, state: "failed", event: "failed",
                       error: error as? AgentError ?? AgentError("provider_unavailable", "A provider worker could not be created."))
                continue
            }
            queue.removeFirst()
            pending[id] = nil
            entries[id]?.lease = lease
            entries[id]?.runner = lease.worker.runner
            entries[id]?.record.worker_reused = lease.reused
            entries[id]?.record.status = "running"
            entries[id]?.record.running_at = Date()
            recordPhase(id, "queue_seconds", Date().timeIntervalSince(entries[id]!.record.started_at))
            logState(id)
            emit(id, "status", ["status": .string("running")])
            entries[id]?.task = Task { await self.perform(id, work: work, lease: lease) }
            entries[id]?.timer = Task {
                do { try await Task.sleep(for: .seconds(self.timeoutSeconds)) } catch { return }
                self.timeout(id)
            }
        }
    }
    private func reapIdleWorkers() {
        for (id, worker) in pool.idleWorkers where !worker.healthy || !worker.reusable {
            pool.beginRetiring(id)
            Task {
                await worker.shutdown()
                self.pool.removed(id)
                self.pump()
            }
        }
    }
    private func queueBlocked(_ reason: String) {
        for id in queue {
            var reasons = entries[id]?.record.queue_reasons ?? []
            if !reasons.contains(reason) {
                reasons.append(reason)
                entries[id]?.record.queue_reasons = reasons
                logState(id)
            }
        }
        // Free an idle cached process before allowing pressure to starve queued
        // work. Busy processes remain protected; cache size is an upper bound.
        if reason != "process_limit", let (id, worker) = pool.oldestIdle {
            pool.beginRetiring(id)
            Task {
                await worker.shutdown()
                self.pool.removed(id)
                self.pump()
            }
        }
    }
    private func recordPhase(_ id: String, _ name: String, _ seconds: Double) {
        guard seconds.isFinite, ["readiness_seconds", "preparation_seconds", "queue_seconds", "worker_checkout_seconds",
            "provider_startup_seconds", "generation_seconds", "validation_seconds", "cleanup_seconds", "total_seconds"].contains(name) else { return }
        if entries[id]?.record.phase_timings == nil { entries[id]?.record.phase_timings = [:] }
        entries[id]?.record.phase_timings?[name] = max(0, seconds)
    }
    private func release(_ lease: ProviderWorkerPool.Lease, healthy: Bool) async {
        if let worker = pool.release(lease.id, healthy: healthy) {
            await worker.shutdown()
            pool.removed(lease.id)
        }
    }
    private func timeout(_ id: String) {
        guard let entry = entries[id], !terminal(entry.record.status) else { return }
        entries[id]?.timedOut = true
        _ = try? cancel(id)
    }
    private func perform(_ id: String, work: Work, lease: ProviderWorkerPool.Lease) async {
        let directory = runtimeRoot.appendingPathComponent(id, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let checkout = Date()
            await lease.evicted?.shutdown()
            pool.evictionFinished(lease.id)
            recordPhase(id, "worker_checkout_seconds", Date().timeIntervalSince(checkout))
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let result = try await lease.worker.execute(
                definition: work.definition, input: work.input, directory: directory,
                timeoutSeconds: timeoutSeconds,
                onOutput: { text in await self.providerOutput(id, text: text) },
                onProgress: { progress in await self.providerProgress(id, progress: progress) },
                onPhase: { name, seconds in await self.recordPhase(id, name, seconds) })
            guard entries[id]?.record.status != "cancelling" else { throw CancellationError() }
            let validation = Date()
            if result["error"] != nil {
                entries[id]?.record.schema_validated = false
                recordPhase(id, "validation_seconds", Date().timeIntervalSince(validation))
                let cleanup = Date()
                await release(lease, healthy: false)
                guard entries[id]?.record.status != "cancelling" else { throw CancellationError() }
                recordPhase(id, "cleanup_seconds", Date().timeIntervalSince(cleanup))
                // Preserve develop's direct feasibility error / HTTP 422 flow,
                // while retiring the request's worker on an error result.
                emit(id, "result", ["result": result])
                finish(id, state: "completed", event: "completed")
                return
            }
            try OutputValidator.validate(result, schema: work.definition.outputSchema)
            recordPhase(id, "validation_seconds", Date().timeIntervalSince(validation))
            entries[id]?.record.schema_validated = true
            let cleanup = Date()
            try await lease.worker.reset()
            guard entries[id]?.record.status != "cancelling" else { throw CancellationError() }
            if let retired = pool.release(lease.id, healthy: true) {
                await retired.shutdown()
                pool.removed(lease.id)
                guard entries[id]?.record.status != "cancelling" else { throw CancellationError() }
            }
            let existingCleanup = entries[id]?.record.phase_timings?["cleanup_seconds"] ?? 0
            recordPhase(id, "cleanup_seconds", existingCleanup + Date().timeIntervalSince(cleanup))
            emit(id, "result", ["result": result])
            finish(id, state: "completed", event: "completed")
        } catch {
            let cleanup = Date()
            await release(lease, healthy: false)
            let existingCleanup = entries[id]?.record.phase_timings?["cleanup_seconds"] ?? 0
            recordPhase(id, "cleanup_seconds", existingCleanup + Date().timeIntervalSince(cleanup))
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
        if var record = entries[id]?.record {
            record.updateElapsed()
            let formatter = ISO8601DateFormatter()
            data["started_at"] = .string(formatter.string(from: record.started_at))
            data["elapsed_seconds"] = .number(record.elapsed_seconds)
            if let runningAt = record.running_at {
                data["running_at"] = .string(formatter.string(from: runningAt))
            }
            if let endedAt = record.ended_at {
                data["ended_at"] = .string(formatter.string(from: endedAt))
            }
        }
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
        entries[id]?.record.updateElapsed()
        entries[id]?.record.error = failure
        if let began = entries[id]?.requestBegan { recordPhase(id, "total_seconds", Date().timeIntervalSince(began)) }
        if let failure, let data = try? JSONEncoder().encode(failure),
            let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        {
            emit(id, event, ["error": json])
        } else {
            emit(id, event, ["status": .string(state)])
        }
        entries[id]?.record.retainOnlyStateTimingAndError()
        logState(id)
        entries[id]?.runner = nil
        entries[id]?.lease = nil
        entries[id]?.timer?.cancel()
        entries[id]?.timer = nil
        entries[id]?.task = nil
        entries[id]?.continuation?.finish()
        entries[id]?.continuation = nil
        print("execution=\(id) state=\(state) code=\(failure?.code ?? "none")")
        pump()
    }
}
