import Foundation

/// Framed stdio transport with bounded input and explicit RPC deadlines. One
/// actor owns the connection; provider callbacks never inspect raw stderr.
actor JSONRPCProcess {
    let runner: ProcessRunner
    private let executable: URL
    private let arguments: [String]
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var pendingMethods: [Int: String] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var launched: CheckedContinuation<Void, any Error>?
    private var task: Task<Void, Never>?
    private var closed = false
    private var handler: (@Sendable (JSONValue) async throws -> Void)?

    init(runner: ProcessRunner, executable: URL, arguments: [String]) {
        self.runner = runner
        self.executable = executable
        self.arguments = arguments
    }
    func setHandler(_ handler: @escaping @Sendable (JSONValue) async throws -> Void) { self.handler = handler }
    func start() async throws {
        guard task == nil, !closed else { return }
        try await withCheckedThrowingContinuation { continuation in
            launched = continuation
            task = Task {
                do {
                    _ = try await runner.runSession(
                        executable: executable, arguments: arguments, timeoutSeconds: 0, keepInputOpen: true,
                        onStarted: { await self.didLaunch() },
                        onLine: { line in try await self.receive(line) })
                    await finished(AgentError("provider_worker_stopped", "The provider worker exited."))
                } catch { await finished(error) }
            }
        }
    }
    private func didLaunch() { launched?.resume(); launched = nil }
    func request(_ method: String, _ params: JSONValue = .object([:]), timeoutSeconds: Int = 20) async throws -> JSONValue {
        guard !closed else { throw AgentError("provider_worker_stopped", "The provider worker exited.") }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            pendingMethods[id] = method
            do {
                try send(.object(["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method), "params": params]))
                deadlines[id] = Task {
                    do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
                    expire(id)
                }
            } catch { resolve(id, result: .failure(error)) }
        }
    }
    func notify(_ method: String, _ params: JSONValue = .object([:])) throws {
        try send(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]))
    }
    private func send(_ value: JSONValue) throws {
        var data = try value.data()
        guard data.count <= 4_194_304 else { throw AgentError("provider_input_limit", "The provider request is too large.") }
        data.append(10)
        try runner.send(data)
    }
    private func receive(_ line: String) async throws {
        guard let value = try? JSONValue.parse(line) else { return }
        if let method = value["method"]?.string {
            if let id = value["id"] {
                // Never automatically grant interactive filesystem/tool approvals.
                if method == "session/request_permission" {
                    try send(.object(["jsonrpc": .string("2.0"), "id": id, "result": .object([
                        "outcome": .object(["outcome": .string("cancelled")]),
                    ])]))
                } else if method.hasSuffix("requestApproval") {
                    try send(.object(["id": id, "result": .object(["decision": .string("decline")])]))
                } else {
                    try send(.object(["jsonrpc": .string("2.0"), "id": id, "error": .object([
                        "code": .number(-32601), "message": .string("Interactive client operations are unavailable."),
                    ])]))
                }
            } else { try await handler?(value) }
        } else if let valueID = value["id"], case .number(let number) = valueID, let id = Int(exactly: number) {
            if let errorObj = value["error"] {
                let method = pendingMethods[id] ?? "session operation"
                let errorCode = errorObj["code"]?.number.flatMap { Int(exactly: $0) }
                let rawMessage = errorObj["message"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rawData = errorObj["data"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let combined = !rawMessage.isEmpty && !rawData.isEmpty ? "\(rawMessage) (\(rawData))" : (!rawMessage.isEmpty ? rawMessage : rawData)
                let isRateLimited = errorCode == -32003
                    || combined.localizedCaseInsensitiveContains("rate limit")
                    || combined.localizedCaseInsensitiveContains("too many requests")
                    || combined.localizedCaseInsensitiveContains("429")
                    || combined.localizedCaseInsensitiveContains("usage-exhausted")
                    || combined.localizedCaseInsensitiveContains("quota")
                if isRateLimited {
                    let desc = combined.isEmpty ? "The provider rate limited the request." : combined
                    resolve(id, result: .failure(AgentError("provider_rate_limited", "The provider rate limited '\(method)': \(desc)")))
                } else {
                    let desc = combined.isEmpty ? "The provider rejected a required session operation." : combined
                    resolve(id, result: .failure(AgentError("provider_protocol_error", "The provider rejected '\(method)': \(desc)")))
                }
            } else { resolve(id, result: .success(value["result"] ?? .object([:]))) }
        }
    }
    private func expire(_ id: Int) {
        let method = pendingMethods[id] ?? "session operation"
        resolve(id, result: .failure(AgentError("provider_protocol_timeout", "The provider '\(method)' operation timed out.")))
    }
    private func resolve(_ id: Int, result: Result<JSONValue, any Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pendingMethods.removeValue(forKey: id)
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    private func finished(_ error: any Error) async {
        closed = true
        launched?.resume(throwing: error)
        launched = nil
        for id in Array(pending.keys) { resolve(id, result: .failure(error)) }
        try? await handler?(.object(["method": .string("transport/closed")]))
    }
    func shutdown() async {
        await runner.stop()
        await task?.value
        handler = nil
    }
}
