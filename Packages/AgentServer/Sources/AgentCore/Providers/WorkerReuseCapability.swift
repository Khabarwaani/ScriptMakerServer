import Foundation

final class WorkerReuseCapability: @unchecked Sendable {
    private let lock = NSLock()
    private var unsupported = false
    var blocked: Bool { lock.withLock { unsupported } }
    func block() { lock.withLock { unsupported = true } }
}

/// Capability fallback is permitted only before any inference has been sent.
/// A failed generation or reset is never replayed.
final class CapabilityGatedWorker: ProviderWorker, @unchecked Sendable {
    private let lock = NSLock()
    private var active: any ProviderWorker
    private let provider: CLIProvider
    private let ownership: WorkerOwnershipStore?
    init(primary: any ProviderWorker, provider: CLIProvider, ownership: WorkerOwnershipStore?) {
        active = primary; self.provider = provider; self.ownership = ownership
    }
    private var worker: any ProviderWorker { lock.withLock { active } }
    var runner: ProcessRunner { worker.runner }
    var reusable: Bool { worker.reusable }
    var healthy: Bool { worker.healthy }
    func execute(
        definition: AgentDefinition, input: JSONValue, directory: URL, timeoutSeconds: Int,
        onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void,
        onPhase: @escaping @Sendable (String, Double) async -> Void
    ) async throws -> JSONValue {
        let began = Date()
        do {
            return try await worker.execute(definition: definition, input: input, directory: directory,
                timeoutSeconds: timeoutSeconds, onOutput: onOutput, onProgress: onProgress, onPhase: onPhase)
        } catch let error as AgentError where error.code == "provider_reset_unsupported" {
            await worker.shutdown()
            try Task.checkCancellation()
            let fresh = FreshProviderWorker(provider: provider, ownership: ownership)
            lock.withLock { active = fresh }
            await onProgress(.object(["message": .string("Persistent reset is unavailable; using a fresh provider process.")]))
            let preflight = Date().timeIntervalSince(began)
            return try await fresh.execute(definition: definition, input: input, directory: directory,
                timeoutSeconds: timeoutSeconds, onOutput: onOutput, onProgress: onProgress,
                onPhase: { name, seconds in await onPhase(name, seconds + (name == "provider_startup_seconds" ? preflight : 0)) })
        }
    }
    func reset() async throws { try await worker.reset() }
    func shutdown() async { await worker.shutdown() }
}
