import Foundation

public struct ExecuteRequest: Codable, Sendable {
    public let agent_id: String
    public let version: String?
    public let provider: String
    public let input: JSONValue
    public init(agentID: String, version: String? = nil, provider: String, input: JSONValue) {
        self.agent_id = agentID
        self.version = version
        self.provider = provider
        self.input = input
    }
}

public struct StreamEvent: Sendable {
    public let name: String
    public let data: JSONValue
    public func sse() throws -> String { "event: \(name)\ndata: \(try data.text())\n\n" }
}

public struct ExecutionRecord: Codable, Sendable {
    public let execution_id: String
    public var agent_id: String?
    public var version: String?
    public var provider: String?
    public var status: String
    public var streaming: Bool?
    public let started_at: Date
    public var running_at: Date?
    public var ended_at: Date?
    public var elapsed_seconds: Double = 0
    public var phase_timings: [String: Double]?
    public var queue_reasons: [String]?
    public var worker_reused: Bool?
    public var error: AgentError?
    public var schema_validated: Bool?
    public var process_id: Int32?
    public var resident_memory_bytes: UInt64?

    mutating func updateElapsed(at now: Date = Date()) {
        elapsed_seconds = running_at.map { max(0, (ended_at ?? now).timeIntervalSince($0)) } ?? 0
    }

    mutating func retainOnlyStateTimingAndError() {
        agent_id = nil
        version = nil
        provider = nil
        streaming = nil
        if let error {
            // Bound retained diagnostics even if a provider supplies a large error.
            self.error = AgentError(
                String(error.code.prefix(128)), String(error.message.prefix(1024)),
                executionID: execution_id, details: Self.processDetails(error))
        }
        schema_validated = nil
        process_id = nil
        resident_memory_bytes = nil
    }

    private static func processDetails(_ error: AgentError) -> JSONValue? {
        guard error.code == "provider_execution_failed" || error.code == "provider_initialization_failed",
              let reason = error.details?["termination_reason"]?.string,
              reason == "exit" || reason == "signal" else { return nil }
        let key = reason == "exit" ? "exit_code" : "signal"
        guard case .number(let status) = error.details?[key], status.isFinite,
              status.rounded() == status, status >= Double(Int32.min), status <= Double(Int32.max)
        else { return nil }
        return .object(["termination_reason": .string(reason), key: .number(status)])
    }
}

public struct AcceptedExecution: Sendable {
    public let id: String
    public let events: AsyncStream<StreamEvent>
}

public struct ExecutionSnapshot: Sendable {
    public let records: [ExecutionRecord]
    public let activeCount: Int
    public let queuedCount: Int
    public let residentMemoryBytes: UInt64
    public let accepting: Bool
    public var worker_pool: WorkerPoolSnapshot? = nil
}
