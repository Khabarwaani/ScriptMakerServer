import Foundation

public protocol ProviderWorker: AnyObject, Sendable {
    var runner: ProcessRunner { get }
    var reusable: Bool { get }
    var healthy: Bool { get }
    func execute(
        definition: AgentDefinition, input: JSONValue, directory: URL, timeoutSeconds: Int,
        onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void,
        onPhase: @escaping @Sendable (String, Double) async -> Void
    ) async throws -> JSONValue
    func reset() async throws
    func shutdown() async
}

final class FreshProviderWorker: ProviderWorker {
    let runner: ProcessRunner
    let provider: any AIProvider
    var reusable: Bool { false }
    var healthy: Bool { true }
    init(provider: any AIProvider, ownership: WorkerOwnershipStore?) {
        self.provider = provider
        runner = ProcessRunner(ownership: ownership)
    }
    func execute(
        definition: AgentDefinition, input: JSONValue, directory: URL, timeoutSeconds: Int,
        onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void,
        onPhase: @escaping @Sendable (String, Double) async -> Void
    ) async throws -> JSONValue {
        let began = Date()
        do {
            let result = try await provider.execute(
                definition: definition, input: input, runner: runner, directory: directory,
                timeoutSeconds: timeoutSeconds, onOutput: onOutput, onProgress: onProgress)
            await report(began, onPhase: onPhase)
            return result
        } catch {
            await report(began, onPhase: onPhase)
            throw error
        }
    }
    private func report(_ began: Date, onPhase: @Sendable (String, Double) async -> Void) async {
        let timing = runner.timing
        guard let launched = timing.launched else { return }
        let ready = timing.ready ?? launched
        await onPhase("provider_startup_seconds", max(0, ready.timeIntervalSince(began)))
        let end = timing.result ?? timing.exited ?? Date()
        await onPhase("generation_seconds", max(0, end.timeIntervalSince(ready)))
        if let result = timing.result, let exited = timing.exited {
            await onPhase("cleanup_seconds", max(0, exited.timeIntervalSince(result)))
        }
    }
    func reset() async throws {}
    func shutdown() async { await runner.stop() }
}
