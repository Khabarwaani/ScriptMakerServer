import Foundation

public struct ProviderSettings: Codable, Sendable {
    public var executable: String
    public var model: String?
    public var enabled: Bool
    public var reasoning_effort: String?
    public var worker_reuse: Bool?
    public init(executable: String, model: String? = nil, enabled: Bool = true,
                reasoningEffort: String? = nil, workerReuse: Bool? = nil) {
        self.executable = executable
        self.model = model
        self.enabled = enabled
        self.reasoning_effort = reasoningEffort
        self.worker_reuse = workerReuse
    }
}

public struct ProviderStatus: Codable, Sendable {
    public let id: String
    public let available: Bool
    public let readiness: String
    public var worker_reuse: String? = nil
}

public protocol AIProvider: Sendable {
    var id: String { get }
    var isAvailable: Bool { get }
    func checkReadiness() async throws
    var workerReuseMode: String { get }
    func makeWorker(ownership: WorkerOwnershipStore?) throws -> any ProviderWorker
    func execute(
        definition: AgentDefinition, input: JSONValue, runner: ProcessRunner, directory: URL,
        timeoutSeconds: Int, onOutput: @escaping @Sendable (String) async -> Void,
        onProgress: @escaping @Sendable (JSONValue) async -> Void
    ) async throws -> JSONValue
}

extension AIProvider {
    public var isAvailable: Bool { true }
    public var workerReuseMode: String { "fresh" }
    public func makeWorker(ownership: WorkerOwnershipStore?) throws -> any ProviderWorker {
        FreshProviderWorker(provider: self, ownership: ownership)
    }
}

public actor ProviderCatalog {
    private let providers: [String: any AIProvider]
    private var readiness: [String: (Date, Task<Void, any Error>)] = [:]
    private var readinessStates: [String: String] = [:]
    public init(providers: [any AIProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func resolve(_ id: String) async throws -> any AIProvider {
        guard let provider = providers[id] else {
            throw AgentError("unsupported_provider", "The selected provider is not configured or supported.")
        }
        let task: Task<Void, any Error>
        if let cached = readiness[id], Date().timeIntervalSince(cached.0) < 30 {
            task = cached.1
        } else {
            task = Task { try await provider.checkReadiness() }
            readiness[id] = (Date(), task)
        }
        do {
            try await task.value
            readinessStates[id] = "ready"
        } catch {
            readinessStates[id] = "unavailable"
            throw error
        }
        return provider
    }
    public func statuses() -> [ProviderStatus] {
        providers.keys.sorted().map {
            ProviderStatus(
                id: $0, available: providers[$0]!.isAvailable, readiness: readinessStates[$0] ?? "unchecked",
                worker_reuse: providers[$0]!.workerReuseMode)
        }
    }
}
