import Foundation

/// New native contexts for each lease; reset releases the prior context before
/// this process may re-enter the idle pool. No conversational "clear" prompts.
actor RPCProviderWorker: ProviderWorker {
    nonisolated let runner: ProcessRunner
    nonisolated var reusable: Bool { !capability.blocked }
    nonisolated var healthy: Bool { runner.healthy }
    private let kind: CLIProvider.Kind
    private let settings: ProviderSettings
    private let rpc: JSONRPCProcess
    private nonisolated let capability: WorkerReuseCapability
    private var initialized = false
    private var contextID: String?
    private var text = ""
    private var completed: Result<JSONValue, any Error>?
    private var completion: CheckedContinuation<JSONValue, any Error>?
    private var onOutput: (@Sendable (String) async -> Void)?
    private var onProgress: (@Sendable (JSONValue) async -> Void)?

    init(kind: CLIProvider.Kind, settings: ProviderSettings, executable: URL, ownership: WorkerOwnershipStore?, capability: WorkerReuseCapability) {
        self.kind = kind
        self.settings = settings
        self.capability = capability
        runner = ProcessRunner(ownership: ownership)
        rpc = JSONRPCProcess(runner: runner, executable: executable,
                             arguments: kind == .codex ? ["app-server", "--stdio"] : ["agent", "--no-leader", "stdio"])
    }
    func execute(
        definition: AgentDefinition, input: JSONValue, directory: URL, timeoutSeconds: Int,
        onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void,
        onPhase: @escaping @Sendable (String, Double) async -> Void
    ) async throws -> JSONValue {
        guard contextID == nil else { throw AgentError("worker_reset_failed", "The previous provider context was not released.") }
        self.onOutput = onOutput
        self.onProgress = onProgress
        text = ""
        completed = nil
        let began = Date()
        if !initialized {
            do {
            await rpc.setHandler { try await self.receive($0) }
            try await rpc.start()
            let parameters: JSONValue = kind == .codex
                ? .object(["clientInfo": .object(["name": .string("agentserver"), "version": .string("2.0.0")])])
                : .object(["protocolVersion": .number(1), "clientCapabilities": .object([:]),
                           "clientInfo": .object(["name": .string("agentserver"), "version": .string("2.0.0")])])
            let capabilities = try await rpc.request("initialize", parameters)
            if kind == .grok && capabilities["agentCapabilities"]?["sessionCapabilities"]?["close"] == nil {
                capability.block()
                throw AgentError("provider_reset_unsupported", "The installed Grok worker cannot close request sessions. Disable worker_reuse for this provider.")
            }
            if kind == .codex { try await rpc.notify("initialized") }
            initialized = true
            runner.markProviderReady()
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                // No context or prompt has been sent: switching to the fresh
                // adapter here cannot replay inference or its tool side effects.
                capability.block()
                throw AgentError("provider_reset_unsupported", "Persistent session setup/reset is unavailable; a fresh process is required.")
            }
        }
        let schema = kind == .codex ? CodexOutputSchema.executionSchema(definition.outputSchema) : nil
        let prompt = try CLIProvider.prompt(definition: definition, input: input, nativeEnvelope: schema != nil)
        if kind == .codex {
            var params: [String: JSONValue] = [
                "cwd": .string(directory.path), "approvalPolicy": .string("never"), "sandbox": .string("read-only"),
                "ephemeral": .bool(false), "persistExtendedHistory": .bool(false),
            ]
            if let model = settings.model { params["model"] = .string(model) }
            let startedThread = try await rpc.request("thread/start", .object(params))
            contextID = startedThread["thread"]?["id"]?.string
            guard let contextID else { throw AgentError("provider_protocol_error", "Codex did not create a request thread.") }
            await onPhase("provider_startup_seconds", Date().timeIntervalSince(began))
            let generated = Date()
            var turn: [String: JSONValue] = [
                "threadId": .string(contextID), "input": .array([.object(["type": .string("text"), "text": .string(prompt)])]),
            ]
            if let schema { turn["outputSchema"] = schema }
            if let effort = settings.reasoning_effort { turn["effort"] = .string(effort) }
            _ = try await rpc.request("turn/start", .object(turn))
            let result = try await waitForCompletion()
            await onPhase("generation_seconds", Date().timeIntervalSince(generated))
            return schema == nil ? result : try CodexOutputSchema.executionResult(result, schema: definition.outputSchema)
        } else {
            let result = try await rpc.request("session/new", .object(["cwd": .string(directory.path), "mcpServers": .array([])]))
            contextID = result["sessionId"]?.string
            guard let contextID else { throw AgentError("provider_protocol_error", "Grok did not create a request session.") }
            // Select read-only plan mode if this installed session advertises it.
            if result["modes"]?["availableModes"]?.array?.contains(where: { $0["id"]?.string == "plan" }) == true {
                _ = try await rpc.request("session/set_mode", .object(["sessionId": .string(contextID), "modeId": .string("plan")]))
            }
            await onPhase("provider_startup_seconds", Date().timeIntervalSince(began))
            let generated = Date()
            let response = try await rpc.request("session/prompt", .object([
                "sessionId": .string(contextID), "prompt": .array([.object(["type": .string("text"), "text": .string(prompt)])]),
            ]), timeoutSeconds: timeoutSeconds)
            await onPhase("generation_seconds", Date().timeIntervalSince(generated))
            guard response["stopReason"]?.string == "end_turn", let result = try? JSONValue.parse(text) else {
                throw AgentError("invalid_final_json", "Grok did not return a complete final JSON value.")
            }
            return result
        }
    }
    private func receive(_ event: JSONValue) async throws {
        let method = event["method"]?.string ?? ""
        if method == "transport/closed" {
            finish(.failure(AgentError("provider_worker_stopped", "The provider worker exited during the request.")))
            return
        }
        let params = event["params"] ?? .object([:])
        if kind == .codex {
            guard let contextID, params["threadId"]?.string == contextID else { return }
            if method == "item/agentMessage/delta", let delta = params["delta"]?.string {
                text += delta
                await onOutput?(delta)
            }
            if method == "item/completed", params["item"]?["type"]?.string == "agentMessage",
               let final = params["item"]?["text"]?.string { text = final }
            if method == "turn/completed" {
                let status = params["turn"]?["status"]?.string
                if status == "completed", let value = try? JSONValue.parse(text) { finish(.success(value)) }
                else if status == "interrupted" { finish(.failure(CancellationError())) }
                else { finish(.failure(AgentError("provider_execution_failed", "Codex did not complete with valid final JSON."))) }
            } else if method == "item/started" || method == "item/completed" {
                await onProgress?(.object(["message": .string("Codex \(params["item"]?["type"]?.string ?? "step") \(method == "item/started" ? "started" : "completed")")]))
            }
        } else {
            guard let contextID, params["sessionId"]?.string == contextID, method == "session/update" else { return }
            let update = params["update"] ?? .object([:])
            // ACP streams the assistant's pre-tool commentary as ordinary
            // message chunks. Tool activity ends that provisional segment;
            // only the final segment after the last tool is a result candidate.
            // Do not search arbitrary text for an embedded JSON object.
            if ["tool_call", "tool_call_update"].contains(update["sessionUpdate"]?.string ?? "") { text = "" }
            if update["sessionUpdate"]?.string == "agent_message_chunk", let delta = update["content"]?["text"]?.string {
                text += delta
                await onOutput?(delta)
            } else {
                await onProgress?(.object(["message": .string("Grok \(update["sessionUpdate"]?.string ?? "step")")]))
            }
        }
        guard text.utf8.count <= 4_194_304 else { throw AgentError("provider_output_limit", "The provider response exceeded the result limit.") }
    }
    private func finish(_ result: Result<JSONValue, any Error>) {
        completed = result
        completion?.resume(with: result)
        completion = nil
    }
    private func waitForCompletion() async throws -> JSONValue {
        if let completed { return try completed.get() }
        return try await withCheckedThrowingContinuation { completion = $0 }
    }
    func reset() async throws {
        guard let contextID else { return }
        do {
            if kind == .codex {
                _ = try await rpc.request("thread/delete", .object(["threadId": .string(contextID)]), timeoutSeconds: 5)
                let loaded = try await rpc.request("thread/loaded/list", timeoutSeconds: 5)
                guard loaded["data"]?.array?.contains(.string(contextID)) == false else {
                    throw AgentError("worker_reset_failed", "Codex did not release the request context.")
                }
            } else {
                let closed = try await rpc.request("session/close", .object(["sessionId": .string(contextID)]), timeoutSeconds: 5)
                guard closed["_meta"]?["x.ai/closeOutcome"]?.string == "closed" else {
                    throw AgentError("worker_reset_failed", "Grok did not close the request context.")
                }
            }
        } catch {
            capability.block()
            throw AgentError("worker_reset_failed", "The provider request context could not be released; the worker was retired.")
        }
        self.contextID = nil
        text = ""
        completed = nil
        onOutput = nil
        onProgress = nil
    }
    func shutdown() async {
        // Only ever delete/close the context this worker created for its request.
        if healthy { try? await reset() }
        await rpc.shutdown()
        contextID = nil
        text = ""
        completed = nil
        onOutput = nil
        onProgress = nil
    }
}
